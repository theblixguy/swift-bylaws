import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Interpreted and compiled rules are equivalent")
struct EquivalenceTests {
  @Test("An inheritance rule agrees in both implementations")
  func inheritanceRuleIsEquivalent() async throws {
    let project = try TemporaryProject(files: Self.sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "ViewModels inherit from BaseViewModel") {
        app.classes.suffixed("ViewModel").violations(of: .inherits(from: "BaseViewModel"))
      }
      """],
      uniquingKeysWith: { first, _ in first }
    ))

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let compiled = try await Self.compiledCodebase(root: project.rootURL.path)
      .classes.suffixed("ViewModel")
      .violations(of: .inherits(from: "BaseViewModel"))
      .erased()

    #expect(interpreted.rule == compiled.rule)
    #expect(interpreted.checkedCount == compiled.checkedCount)
    #expect(interpreted.offenders.map(\.name) == compiled.offenders.map(\.name))
    #expect(
      interpreted.offenders.map(\.location)
        == compiled.offenders.map(\.location)
    )
    #expect(interpreted == compiled)
  }

  @Test("A composed ban agrees in both implementations")
  func composedBanIsEquivalent() async throws {
    let project = try TemporaryProject(files: Self.sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "The domain stays free of UI frameworks") {
        app.files.under("Sources/Domain").violations(matching: .imports("UIKit") || .imports("SwiftUI"))
      }
      """],
      uniquingKeysWith: { first, _ in first }
    ))

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let compiled = try await Self.compiledCodebase(root: project.rootURL.path)
      .files.under("Sources/Domain")
      .violations(matching: .imports("UIKit") || .imports("SwiftUI"))
      .erased()

    #expect(interpreted == compiled)
  }

  @Test("A rule over every type agrees in both implementations")
  func typeQueryIsEquivalent() async throws {
    let project = try TemporaryProject(files: Self.sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Types outside the domain are classes") {
        app.types.outside("Sources/Domain").violations(of: .isClass)
      }
      """],
      uniquingKeysWith: { first, _ in first }
    ))

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let compiled = try await Self.compiledCodebase(root: project.rootURL.path)
      .types.outside("Sources/Domain")
      .violations(of: .isClass)
      .erased()

    #expect(interpreted == compiled)
  }

  @Test("Parent paths cannot leave the root in either implementation")
  func parentPathsCannotLeaveRoot() async throws {
    let project = try TemporaryProject(files: Self.sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("outside", "All files are outside the parent") {
        app.files.outside("..").violations(matching: .imports("UIKit"))
      }
      """],
      uniquingKeysWith: { first, _ in first }
    ))

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let files = try await Self.compiledCodebase(root: project.rootURL.path)
      .files
    let compiled = files.outside("..")
      .violations(matching: .imports("UIKit")).erased()

    #expect(interpreted == compiled)
    #expect(compiled.checkedCount == 3)
  }

  @Test("A negated matcher agrees in both implementations")
  func negatedMatcherIsEquivalent() async throws {
    let project = try TemporaryProject(files: Self.sources.merging(
      ["Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "ViewModels say final unless public") {
        app.classes.suffixed("ViewModel").violations(matching: !.isFinal && !.isPublic)
      }
      """],
      uniquingKeysWith: { first, _ in first }
    ))

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let compiled = try await Self.compiledCodebase(root: project.rootURL.path)
      .classes.suffixed("ViewModel")
      .violations(matching: !.isFinal && !.isPublic)
      .erased()

    #expect(interpreted == compiled)
  }

  @Test("Parentheses control matcher grouping")
  func parenthesisedMatcherIsEquivalent() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Classes are final and public or documented") {
        app.classes.violations(of: .isFinal && (.isPublic || .hasDocumentation))
      }
      """,
      "Sources/App/Classes.swift": """
      final class InternalFinal {}
      /// Documentation.
      class Documented {}
      public final class PublicFinal {}
      """,
    ])

    let interpreted = try await #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    ).violations()
    let compiled = try await Self.compiledCodebase(root: project.rootURL.path)
      .classes
      .violations(of: .isFinal && (.isPublic || .hasDocumentation))
      .erased()

    #expect(interpreted == compiled)
    #expect(Set(interpreted.offenders.map(\.name)) == [
      "Documented", "InternalFinal",
    ])
  }

  private static let sources: [String: String] = [
    "Sources/App/Screens.swift": """
    class HomeViewModel {}
    final class SettingsViewModel: BaseViewModel {}
    public class ProfileViewModel {}
    """,
    "Sources/Domain/User.swift": "import UIKit\nstruct User {}",
    "Sources/Domain/Order.swift": "import Foundation\nstruct Order {}",
  ]

  private static func compiledCodebase(root: String) -> Codebase {
    Codebase(root: .directory(root), including: ["Sources/**"])
  }
}
