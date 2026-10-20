import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable fix builders")
struct CorrectionBuilderTests {
  @Test("Builder conditions, loops and arrays keep edit order")
  func builderOrder() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("edits") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          let file = try context.file
          if false {
            file.replacement(with: "unused")
          } else {
            for target in file.matches(of: /first|second/) {
              [target.replacement(with: target.text.uppercased())]
            }
          }
        }
      }
      """#,
      sources: [
        "Sources/Model.swift": "class Model { let first = 1; let second = 2 }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = try #require(findings.violations.fixes.compactMap(\.self).first)
      .edits

    #expect(edits.map(\.source.text) == ["first", "second"])
    #expect(edits.map(\.replacement) == ["FIRST", "SECOND"])
  }

  @Test("Explicit return supplies empty or nonempty edits", arguments: [
    (source: "class Model {}", replacements: [String]()),
    (source: "class Other {}", replacements: ["class Updated {}"]),
  ])
  func explicitReturn(source: String, replacements: [String]) async throws {
    let project = try rulesProject(
      rules: """
      Rule("returned") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          guard context.offender.name == "Other" else { return [] }
          return [try context.source.replacement(with: "class Updated {}")]
        }
      }
      """,
      sources: ["Sources/Model.swift": source]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.count == 1)
    #expect(findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == replacements)
    if replacements.isEmpty {
      #expect(findings.violations.fixes == [nil])
    } else {
      let fix = try #require(findings.violations.fixes.compactMap(\.self).first)
      let edit = try #require(fix.edits.first)
      #expect(edit.source.text == "class Other {}")
      #expect(edit.source.range == 0..<14)
    }
  }

  @Test("Nested closure returns preserve outer builder collection")
  func nestedReturn() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("nested") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          let file = try context.file
          let name = try context.offender.nameSource
          file.matches(of: /first|second/).map { target in
            return target.replacement(with: target.text.uppercased())
          }
          name.replacement(with: "Updated")
        }
      }
      """#,
      sources: [
        "Sources/Model.swift": "class Model { let first = 1; let second = 2 }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = try #require(findings.violations.fixes.compactMap(\.self).first)
      .edits

    #expect(edits.map(\.source.text) == ["first", "second", "Model"])
    #expect(edits.map(\.replacement) == ["FIRST", "SECOND", "Updated"])
  }

  @Test("Explicit scalar return reports edit array requirement")
  func scalarReturn() async throws {
    let project = try rulesProject(
      rules: """
      Rule("scalar") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          return try context.source.replacement(with: "class Updated {}")
        }
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let path = project.fileURL(for: "ProjectRules.swift").path
    let program = await RuleProgram.loaded(fromFiles: [path])

    #expect(program.rules.isEmpty)
    #expect(program.errors.contains {
      $0.message.contains("must be [SourceFix.Edit]")
        && $0.location.filePath == path && $0.location.line == 7
    })
  }
}
