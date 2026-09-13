import BylawsCore
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Member literals")
struct MemberLiteralTests {
  @Test(
    "Every source case names a member literal",
    arguments: SupportedAPI.MemberLiteral.Owner.allCases
  )
  func ownersNameEverySourceCase(_ owner: SupportedAPI.MemberLiteral.Owner) {
    let missing = owner.sourceNames
      .filter { SupportedAPI.MemberLiteral(rawValue: $0) == nil }
    #expect(
      missing.isEmpty,
      "\(owner) names \(missing.joined(separator: ", ")) without a literal"
    )
  }

  @Test("Every owner names at least one literal")
  func ownersAreNotEmpty() {
    let empty = SupportedAPI.MemberLiteral.Owner.allCases
      .filter(\.literals.isEmpty)
      .map { String(describing: $0) }
    #expect(empty.isEmpty, "\(empty.joined(separator: ", ")) names no literal")
  }

  @Test("Every member literal belongs to an owner")
  func literalsHaveAnOwner() {
    let orphans = SupportedAPI.MemberLiteral.allCases
      .filter(\.owners.isEmpty)
      .map(\.rawValue)
      .sorted()
    #expect(orphans.isEmpty, "\(orphans.joined(separator: ", ")) has no owner")
  }

  private func program(comparingVisibilityTo literal: String) async throws
    -> RuleProgram
  {
    let project = try rulesProject(
      rules: """
      Rule("visibility", "Classes stay internal") {
        let classes = try await app.classes
        let offenders = classes.filter { $0.visibility == \(literal) }
        return Violations(
          rule: "be internal",
          offenders: offenders,
          checkedCount: classes.count
        )
      },
      """,
      sources: [
        "Sources/App/A.swift": "public class A {}",
      ]
    )
    // The project deletes its directory when it is released.
    defer { withExtendedLifetime(project) {} }
    return await RuleProgram.loaded(
      fromFiles: [
        LexicalFilePath("\(project.rootURL.path)/ProjectRules.swift"),
      ],
      parseCachePolicy: .disabled
    )
  }

  @Test("A misspelled member literal fails the rule")
  func misspelledLiteralDiagnoses() async throws {
    let program = try await program(comparingVisibilityTo: ".publlic")

    let diagnostic = try #require(program.errors.first)
    try expectDiagnostic(
      diagnostic,
      messageContaining: "'.publlic' is not a supported member literal",
      hintContaining: ".public"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A member literal no type declares fails without a suggestion")
  func unrelatedLiteralDiagnoses() async throws {
    let program = try await program(comparingVisibilityTo: ".quuxSplat")

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message == "'.quuxSplat' is not a supported member literal"
    )
    #expect(diagnostic.hint == nil)
    #expect(program.rules.isEmpty)
  }

  @Test("A member literal of another type fails the rule")
  func mismatchedOwnerDiagnoses() async throws {
    let program = try await program(comparingVisibilityTo: ".brew")

    let diagnostic = try #require(program.errors.first)
    #expect(
      diagnostic.message == "'==' does not apply to these values"
    )
    #expect(program.rules.isEmpty)
  }

  @Test("A supported member literal still compiles into a rule")
  func supportedLiteralCompiles() async throws {
    let program = try await program(comparingVisibilityTo: ".public")

    #expect(program.errors.isEmpty)
    #expect(program.rules.count == 1)
  }
}
