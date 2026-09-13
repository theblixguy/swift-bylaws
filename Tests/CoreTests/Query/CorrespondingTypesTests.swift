import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Corresponding type recipes")
struct CorrespondingTypesTests {
  @Test("Views have a view model in the same feature")
  func featureViewModels() async throws {
    let app = Codebase(root: .sources([
      "Sources/Features/Orders/Views/OrderView.swift": "struct OrderView {}",
      "Sources/Features/Orders/ViewModels/OrderViewModel.swift": "class OrderViewModel {}",
      "Sources/Features/Payments/Views/OrderView.swift": "struct OrderView {}",
      "Sources/Features/Profile/Views/ProfileView.swift": "struct ProfileView {}",
    ]), including: ["Sources/Features/**"])
    let views = try await app.types.suffixed("View")
    let viewModels = try await app.types.suffixed("ViewModel")
    let namesByFeature = Dictionary(grouping: viewModels, by: featureFolder)
      .mapValues { Set($0.map(\.name)) }
    let hasViewModel =
      Matcher<NominalType>("have a view model in the same feature") { view in
        namesByFeature[featureFolder(view)]?
          .contains(view.name + "Model") == true
      }

    let violations = Violations(of: hasViewModel, in: views)

    #expect(violations.checkedCount == 3)
    #expect(Set(violations.offenders.map(\.location.filePath)) == [
      "/virtual/Sources/Features/Payments/Views/OrderView.swift",
      "/virtual/Sources/Features/Profile/Views/ProfileView.swift",
    ])
  }

  @Test("Repositories have a corresponding test type")
  func repositoryTests() async throws {
    let project = Codebase(root: .sources([
      "Sources/App/OrderRepository.swift": "class OrderRepository {}",
      "Sources/App/PaymentRepository.swift": "class PaymentRepository {}",
      "Tests/AppTests/OrderRepositoryTests.swift": "struct OrderRepositoryTests {}",
      "Sources/App/PaymentRepositoryTests.swift": "struct PaymentRepositoryTests {}",
    ]), including: ["Sources/**", "Tests/**"])
    let repositories = try await project.types.under("Sources")
      .suffixed("Repository")
    let testNames = Set(try await project.types.under("Tests").map(\.name))
    let hasTests = Matcher<NominalType>("have a corresponding test type") {
      testNames.contains($0.name + "Tests")
    }

    let violations = Violations(of: hasTests, in: repositories)

    #expect(violations.offenders.map(\.name) == ["PaymentRepository"])
  }
}

private func featureFolder(_ type: NominalType) -> String {
  URL(fileURLWithPath: type.location.filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .path
}
