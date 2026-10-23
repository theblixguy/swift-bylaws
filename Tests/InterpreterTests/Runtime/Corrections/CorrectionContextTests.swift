import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction query context")
struct CorrectionContextTests {
  @Test("Path violations retain codebase for cross-file fixes")
  func pathViolations() async throws {
    let project = try rulesProject(
      rules: """
      Rule("paths") {
        try await app.classes.named("Primary")
          .violations(outsidePaths: ["Allowed/**"])
          .withFix { context in
            let companions = try await context.codebase.classes.named("Companion")
            for companion in companions {
              try companion.nameSource.replacement(with: "Helper")
            }
          }
      }
      """,
      sources: [
        "Sources/Primary.swift": "class Primary {}",
        "Sources/Companion.swift": "class Companion {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"]
    )
    let compiled = try await codebase.classes.named("Primary")
      .violations(outsidePaths: ["Allowed/**"])
      .withFix { context in
        let companions = try await context.codebase.classes.named("Companion")
        for companion in companions {
          try companion.nameSource.replacement(with: "Helper")
        }
      }
    let edits = findings.violations.fixes.compactMap(\.self).flatMap(\.edits)

    #expect(findings.violations.offenders.map(\.name) == ["Primary"])
    #expect(findings.violations.fixes == compiled.fixes)
    #expect(edits.map(\.source.filePath) == [
      project.fileURL(for: "Sources/Companion.swift").path,
    ])
    #expect(edits.map(\.source.text) == ["Companion"])
    #expect(edits.map(\.replacement) == ["Helper"])
  }
}
