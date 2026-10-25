import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable layout candidate ownership")
struct LayoutCandidateOwnershipTests {
  @Test(
    "Mixed corrections retain dormant cross-file layouts with offender",
    arguments: [
      "check",
      "check.findings(reportedAt: owners[0].location).violations",
      "check.findings(reportedAt: owners[0].location).checks[0]",
    ]
  )
  func mixedCorrection(expression: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("rename-owner") {
        let owners = try await app.classes.named("Owner")
        let check = try await owners.violations("Rename owner") { owner in
          try owner.nameSource.replacement(with: "Updated")
          for other in try await app.classes.named("Other") {
            try other.attributes.replacement {
              Line { other.attributes }
            }
          }
        }
        \(expression)
      }
      """,
      sources: [
        "Sources/Owner.swift": "class Owner {}",
        "Sources/Other.swift": "@Observable @MainActor\nclass Other {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let violations = findings.violations
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)
    let candidate = try #require(fix.layoutCandidates.first)

    #expect(violations.offenders.map(\.name) == ["Owner"])
    #expect(violations.layoutCandidates.isEmpty)
    #expect(fix.edits.count == 1)
    #expect(edit.source.filePath == project.fileURL(for: "Sources/Owner.swift")
      .path)
    #expect(edit.source.text == "Owner")
    #expect(edit.replacement == "Updated")
    #expect(fix.layoutCandidates.count == 1)
    #expect(candidate.source.filePath == project
      .fileURL(for: "Sources/Other.swift").path)
    #expect(candidate.source.text == "@Observable @MainActor\n")
    #expect(candidate.replacement == "@Observable @MainActor\n")

    let filtered = violations.filteringOffenders { _ in false }

    #expect(filtered.offenders.isEmpty)
    #expect(filtered.fixes.isEmpty)
    #expect(filtered.layoutCandidates.isEmpty)
  }
}
