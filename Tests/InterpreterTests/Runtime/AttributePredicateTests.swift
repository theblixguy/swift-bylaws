import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Portable attribute predicates")
struct PortableAttributePredicateTests {
  @Test("Throwing helpers read captured argument source")
  func sourcePredicate() async throws {
    let project = try project(declarations: #"""
    func selects(_ argument: SourceExpression) throws -> Bool {
      try argument.source.text == "\"second\""
    }
    """#)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)
    #expect(edit.source.text == "Model")
    #expect(edit.replacement == "Updated")
  }

  @Test("Predicate source failures reach rule error")
  func sourceFailure() async throws {
    let project = try project(declarations: """
    func selects(_ argument: SourceExpression) throws -> Bool {
      try argument.source.slice(999..<1000).text.isEmpty
    }
    """)
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)
    await #expect {
      try await rule.findings()
    } throws: { error in
      guard let error = error as? RuleError else { return false }
      return error.description
        .contains(SourceError.rangeOutOfBounds.description)
    }
  }

  @Test("Matching attribute stops later throwing predicates")
  func shortCircuit() async throws {
    let project = try project(declarations: """
    func selects(_ argument: SourceExpression) throws -> Bool {
      if argument.stringValue == "first" { return true }
      return try argument.source.slice(999..<1000).text.isEmpty
    }
    """)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.count == 1)
    #expect(findings.violations.fixes.first??.edits.first?
      .replacement == "Updated")
  }

  @Test("Attribute predicates reject async helpers")
  func asynchronousHelper() async throws {
    let project = try project(declarations: """
    func selects(_ argument: SourceExpression) async -> Bool {
      argument.stringValue == "second"
    }
    """)
    await expectRejection(in: project, containing: "synchronous")
  }

  @Test("Nonthrowing helpers cannot hide source failures")
  func hiddenThrow() async throws {
    let project = try project(declarations: #"""
    func selects(_ argument: SourceExpression) -> Bool {
      try argument.source.text == "\"second\""
    }
    """#)
    await expectRejection(
      in: project,
      containing: "a nonthrowing body cannot call a throwing API"
    )
  }

  @Test(
    "Throwing attribute predicates preserve outer collection limits",
    arguments: [false, true]
  )
  func collectionEffects(afterPredicate: Bool) async throws {
    let body = if afterPredicate {
      """
      let matches = try declaration.hasAttribute("Label", argument: selects)
      let values = [declaration].filter { try $0.source.text.isEmpty }
      if matches && values.isEmpty {
        try declaration.nameSource.replacement(with: "Updated")
      }
      """
    } else {
      """
      let values = [declaration].filter { value in
        try value.hasAttribute("Label", argument: selects)
      }
      if !values.isEmpty {
        try declaration.nameSource.replacement(with: "Updated")
      }
      """
    }
    let project = try project(
      declarations: #"""
      func selects(_ argument: SourceExpression) throws -> Bool {
        try argument.source.text == "\"second\""
      }
      """#,
      body: body
    )
    await expectRejection(
      in: project,
      containing: "a nonthrowing body cannot call a throwing API"
    )
  }

  private func project(
    declarations: String,
    body: String = """
    if try declaration.hasAttribute("Label", argument: selects) {
      try declaration.nameSource.replacement(with: "Updated")
    }
    """
  ) throws -> TemporaryProject {
    let project = try correctionProject(
      declarations: declarations,
      ruleBody: """
      try await app.classes.violations("Update selected label") { declaration in
        \(body)
      }
      """
    )
    try project.write(
      "@Label(\"first\") @Label(\"second\") class Model {}",
      to: "Sources/Model.swift"
    )
    return project
  }

  private func expectRejection(
    in project: TemporaryProject,
    containing message: String
  ) async {
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])
    #expect(program.rules.isEmpty)
    #expect(
      program.errors.contains { $0.message.contains(message) },
      "\(program.errors.map(\.message))"
    )
  }
}
