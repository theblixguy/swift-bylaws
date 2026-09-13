import Bylaws
import Testing

@Suite("Type placement")
struct TypePlacementTests {
  @Test("A declaration can be in any permitted path")
  func permittedPaths() async throws {
    let app = Codebase(root: .sources([
      "Sources/App/Views/Screen.swift": "struct Screen {}",
      "Sources/App/Models/Order.swift": "struct Order {}",
      "Sources/App/Other/Helper.swift": "struct Helper {}",
    ]))
    let result = try await app.types.violations(outsidePaths: [
      "Sources/App/Views/**", "Sources/App/Models/**",
    ])
    #expect(result.offenders.map(\.name) == ["Helper"])
    #expect(result.checkedCount == 3)
  }

  @Test("A view model must be in a view model folder in any feature")
  func featurePlacement() async throws {
    let app = Codebase(root: .sources([
      "Sources/App/Orders/ViewModels/OrderViewModel.swift": "class OrderViewModel {}",
      "Sources/App/Profile/ViewModels/Details/ProfileViewModel.swift": "class ProfileViewModel {}",
      "Sources/App/Orders/Views/MisplacedViewModel.swift": "class MisplacedViewModel {}",
      "Sources/App/ViewModels/LooseViewModel.swift": "class LooseViewModel {}",
    ]))
    let result = try await app.types.suffixed("ViewModel")
      .violations(outsidePaths: "Sources/App/*/ViewModels/**")
    #expect(result.offenders.map(\.name).sorted() == [
      "LooseViewModel",
      "MisplacedViewModel",
    ])
    #expect(result.checkedCount == 4)
  }

  @Test("A protocol can identify views without a name suffix")
  func conformancePlacement() async throws {
    let app = Codebase(root: .sources([
      "Sources/App/Views/Screen.swift": "struct Screen: View {}",
      "Sources/App/Models/Card.swift": "struct Card: View {}",
      "Sources/App/Models/Order.swift": "struct Order {}",
    ]))
    let result = try await app.types.where(.conforms(to: "View"))
      .violations(outsidePaths: ["Sources/App/Views/**"])
    #expect(result.offenders.map(\.name) == ["Card"])
    #expect(result.checkedCount == 2)
  }
}
