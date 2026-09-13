import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable corresponding type recipes")
struct CorrespondingTypesRuleTests {
  @Test("Repository test names checked across source and test selections")
  func repositoryTests() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": #"""
      import Bylaws
      import Testing
      let project = Codebase(including: ["Sources/**", "Tests/**"])
      let rules: [Rule] = [
        Rule("repository-tests", "Repositories have tests") {
          let repositories = try await project.types.under("Sources").suffixed("Repository")
          let testNames = Set(try await project.types.under("Tests").map(\.name))
          let hasTests = Matcher<NominalType>("have a corresponding test type") {
            testNames.contains($0.name + "Tests")
          }
          return repositories.violations(of: hasTests)
        }
      ]
      """#,
      "Sources/App/OrderRepository.swift": "class OrderRepository {}",
      "Sources/App/PaymentRepository.swift": "class PaymentRepository {}",
      "Tests/AppTests/OrderRepositoryTests.swift": "struct OrderRepositoryTests {}",
      "Sources/App/PaymentRepositoryTests.swift": "struct PaymentRepositoryTests {}",
    ])
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.offenders.map(\.name) == ["PaymentRepository"])
  }

  @Test("Compiled and interpreted folder rules report the same violations")
  func featureViews() async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Support/PortableFolderRules.swift")
    let rulesSource = try String(contentsOf: rulesFile, encoding: .utf8)
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": rulesSource + """

      let app = Codebase(including: ["Sources/**"])
      let rules = rulesForFeatureViews(app)
      """,
      "Sources/Features/Orders/Views/OrderView.swift": "class OrderView {}",
      "Sources/Features/Orders/ViewModels/OrderViewModel.swift": "class OrderViewModel {}",
      "Sources/Features/Payments/Views/PaymentView.swift": "class PaymentView {}",
      "Sources/Features/Orders/ViewModels/PaymentViewModel.swift": "class PaymentViewModel {}",
      "Sources/Features/Accounts/Views/AccountView.swift": "class AccountView {}",
    ])
    let program = try await loadedProgram(in: project)
    let app = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    let interpreted = try await #require(program.rules.first).violations()
    let compiled = try await #require(rulesForFeatureViews(app).first)
      .violations()

    #expect(interpreted == compiled)
    #expect(Set(interpreted.offenders.map(\.name)) == [
      "PaymentView",
      "AccountView",
    ])
    #expect(interpreted.checkedCount == 3)
  }

  @Test("Documentation folder rule runs from the CLI")
  func documentedRule() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let guide = try String(
      contentsOf: root
        .appendingPathComponent(
          "Sources/Bylaws/Bylaws.docc/CorrespondingTypes.md"
        ),
      encoding: .utf8
    )
    let example = try #require(guide.components(separatedBy: "```swift\n").last)
      .components(separatedBy: "```")[0]
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": example,
      "Sources/Features/Orders/Views/OrderView.swift": "struct OrderView {}",
      "Sources/Features/Orders/ViewModels/OrderViewModel.swift": "struct OrderViewModel {}",
      "Sources/Features/Payments/Views/PaymentView.swift": "struct PaymentView {}",
    ])
    let program = try await loadedProgram(in: project)

    let violations = try await #require(program.rules.first).violations()

    #expect(violations.offenders.map(\.name) == ["PaymentView"])
    #expect(violations.checkedCount == 2)
  }
}
