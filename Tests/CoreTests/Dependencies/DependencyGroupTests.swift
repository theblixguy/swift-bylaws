import BylawsCore
import Testing

@Suite("Dependency group discovery")
struct DependencyGroupTests {
  @Test("Contextual initialisers use the declared type")
  func contextualInitialiser() {
    let DependencyGroup = "Orders"
    let group: DependencyGroup = .init(
      DependencyGroup,
      files: ["Sources/Orders/**"]
    )

    #expect(group.name == "Orders")
  }

  @Test("Matching folders form sorted groups without a build")
  func folders() async throws {
    let app = Codebase(root: .sources([
      "Sources/Payments/Models/Card.swift": "struct Card {}",
      "Sources/Orders/Models/Order.swift": "struct Order {}",
      "Sources/Orders/Views/OrderView.swift": "struct OrderView {}",
      "Sources/Other/Other.swift": "struct Other {}",
    ]), including: ["Sources/**"], excluding: ["Sources/Other/**"])

    let groups = try await app.dependencyGroups(inFoldersMatching: "Sources/*")

    #expect(groups == [
      .init("Sources/Orders", files: ["Sources/Orders/**"]),
      .init("Sources/Payments", files: ["Sources/Payments/**"]),
    ])
    #expect(try await app.dependencyGroups(inFoldersMatching: "Missing/*")
      .isEmpty)
  }

  @Test("Group names preserve parent paths")
  func repeatedFolderNames() async throws {
    let app = Codebase(root: .sources([
      "Sources/Orders/Models/Order.swift": "struct Order {}",
      "Sources/Payments/Models/Card.swift": "struct Card {}",
    ]))

    let groups = try await app
      .dependencyGroups(inFoldersMatching: "Sources/*/Models")

    #expect(groups.map(\.name) == [
      "Sources/Orders/Models",
      "Sources/Payments/Models",
    ])
  }

  @Test(
    "Unsupported folder patterns fail",
    arguments: [
      "",
      "/Sources/*",
      "Sources//A",
      "../*",
      "./*",
      "Sources\\A",
      "Sources/\0",
    ]
  )
  func unsupportedPattern(_ pattern: String) async {
    let app = Codebase(root: .sources(["App.swift": "struct App {} "]))
    await #expect(throws: DependencyGroupError.unsupportedPattern(pattern)) {
      try await app.dependencyGroups(inFoldersMatching: pattern)
    }
  }

  @Test(
    "Folder names with glob characters cannot broaden a group",
    arguments: ["A*", "A?"]
  )
  func literalFolderNames(_ folder: String) async {
    let app = Codebase(root: .sources([
      "Sources/\(folder)/App.swift": "struct App {}",
      "Sources/AB/Other.swift": "struct Other {}",
    ]))
    await #expect(throws: DependencyGroupError
      .unsupportedFolderPath("Sources/\(folder)"))
    {
      try await app.dependencyGroups(inFoldersMatching: "Sources/*")
    }
  }
}
