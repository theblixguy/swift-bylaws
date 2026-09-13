import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics
import Testing

@Suite("File dependency permissions")
struct DependencyTests {
  private let mock = DependencyCheckMock()

  @Test("Only selected source files are checked")
  func sourceSelection() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.orders, to: mock.payments)],
      pattern: nil,
      from: ["Sources/Shared/**"],
      allowingReferencesTo: []
    )
    #expect(result.violations.checkedCount == 0)
    #expect(result.violations.isEmpty)
  }

  @Test("Files outside folder groups can use any explicitly permitted path")
  func chosenPermissions() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.shared, to: mock.payments)],
      pattern: nil,
      from: ["Sources/Shared/**"],
      allowingReferencesTo: ["Sources/Features/Payments/**"]
    )
    #expect(result.violations.checkedCount == 1)
    #expect(result.violations.isEmpty)
  }

  @Test("References within one file are permitted")
  func sameFile() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.orders, to: mock.orders)],
      pattern: nil,
      allowingReferencesTo: []
    )
    #expect(result.violations.isEmpty)
  }

  @Test("Folder permission applies only within the same matching folder")
  func folderPermission() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.ordersAPI),
      mock.edge(from: mock.orders, to: mock.paymentsAPI),
    ], allowingReferencesTo: [])
    #expect(result.violations.count == 1)
    #expect(result.violations.offenders.first?.name == mock.paymentsAPI)
  }

  @Test("Destination patterns start at the codebase root")
  func destinationRoot() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.orders, to: mock.paymentsAPI)],
      allowingReferencesTo: ["API/**"]
    )
    #expect(result.violations.count == 1)
  }

  @Test("Definitions outside the codebase selection are excluded")
  func externalDependency() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: "/external/Library.swift"),
    ], allowingReferencesTo: [])
    #expect(result.violations.checkedCount == 0)
    #expect(result.violations.isEmpty)
  }

  @Test("Empty source selection produces a warning")
  func emptySources() async throws {
    let result = try await mock.check([], pattern: nil, from: [])
    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.message.contains("matches no files") == true)
  }

  @Test("Implementation references between folders reported")
  func privateDependency() async throws {
    let result = try await mock.check([mock.edge(
      from: mock.orders,
      to: mock.payments
    )])

    #expect(result.violations.checkedCount == 1)
    #expect(result.violations.offenders
      .map(\.location.filePath) == [mock.orders])
    #expect(result.violations.offenders.first?.description
      .contains("Sources/Features/Payments") == true)
  }

  @Test("Same-folder and explicitly permitted references pass", arguments: [
    (
      "Sources/Features/Orders/Model.swift",
      "Sources/Features/Orders/API/OrdersAPI.swift"
    ),
    (
      "Sources/Features/Orders/Model.swift",
      "Sources/Features/Payments/API/PaymentsAPI.swift"
    ),
    ("Sources/Features/Orders/Model.swift", "Sources/Shared/Clock.swift"),
    ("Sources/Shared/Clock.swift", "Sources/Shared/Clock.swift"),
  ])
  func allowedDependency(source: String, destination: String) async throws {
    let result = try await mock.check([mock.edge(
      from: "/virtual/" + source,
      to: "/virtual/" + destination
    )])

    #expect(result.violations.isEmpty)
    #expect(result.violations.checkedCount == 1)
  }

  @Test("A source group can exclude references to the folder groups")
  func sharedDependency() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.shared, to: mock.paymentsAPI)],
      from: ["Sources/Shared/**"],
      allowingReferencesTo: ["Sources/Shared/**"]
    )

    #expect(result.violations.count == 1)
  }

  @Test("Selected files outside permitted paths reported")
  func unassignedDependency() async throws {
    let result = try await mock.check([mock.edge(
      from: mock.orders,
      to: mock.outside
    )])

    #expect(result.violations.count == 1)
  }

  @Test("Reference permissions do not impose cycle restrictions")
  func allowedCycle() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.paymentsAPI),
      mock.edge(from: mock.payments, to: mock.ordersAPI),
      mock.edge(from: mock.orders, to: mock.payments),
    ])

    #expect(result.violations.count == 1)
    #expect(result.violations.offenders.first?.name == mock.payments)
  }

  @Test("Duplicate index occurrences reported once")
  func duplicateReference() async throws {
    let occurrences = mock.edge(from: mock.orders, to: mock.payments)
    let result = try await mock.check([occurrences + occurrences, occurrences])

    #expect(result.violations.count == 1)
    #expect(result.violations.checkedCount == 1)
  }

  @Test("Implicit references excluded")
  func implicitReference() async throws {
    let result = try await mock.check([[
      mock.reference(
        file: mock.payments,
        symbol: mock.payments,
        roles: .definition
      ),
      mock.reference(
        file: mock.orders,
        symbol: mock.payments,
        roles: [.reference, .implicit]
      ),
    ]])

    #expect(result.violations.isEmpty)
    #expect(result.violations.checkedCount == 0)
  }

  @Test("Ambiguous definitions produce a warning")
  func ambiguousDefinition() async throws {
    let result = try await mock.check([[
      mock.reference(file: mock.payments, symbol: "Model", roles: .definition),
      mock.reference(file: mock.orders, symbol: "Model", roles: .definition),
      mock.reference(file: mock.ordersAPI, symbol: "Model", roles: .reference),
    ]])

    #expect(result.violations.isEmpty)
    #expect(result.warnings.map(\.message)
      .contains { $0.contains("cannot assign 'Model'") })
  }

  @Test("Definitions across modules resolve by symbol identity")
  func crossModuleDependency() async throws {
    let result = try await mock.check([[
      mock.reference(
        file: mock.payments,
        symbol: "Model",
        roles: .definition,
        module: "Payments"
      ),
      mock.reference(
        file: mock.orders,
        symbol: "Model",
        roles: .reference,
        module: "Orders"
      ),
    ]])

    #expect(result.violations.count == 1)
  }

  @Test(
    "Unsupported relative patterns rejected",
    arguments: [
      "",
      "/Sources/*",
      "../Features/*",
      "Sources/./*",
      "Sources//Features",
      "Sources\\Features",
      "Sources\0",
    ]
  )
  func unsupportedPattern(pattern: String) async throws {
    await #expect(throws: DependencyCheckError.unsupportedPattern(pattern)) {
      try await mock.check([], pattern: pattern)
    }
  }

  @Test("Nested folder matches rejected")
  func overlappingFolders() async throws {
    await #expect(throws: DependencyCheckError.self) {
      try await mock.check([], pattern: "Sources/Features/**")
    }
  }

  @Test("Source and destination patterns may overlap")
  func overlappingPermissions() async throws {
    let result = try await mock.check(
      [mock.edge(from: mock.orders, to: mock.payments)],
      from: ["Sources/**"],
      allowingReferencesTo: ["Sources/**"]
    )
    #expect(result.violations.isEmpty)
  }

  @Test("Source and destination patterns use the same path validation")
  func unsupportedBoundaryPatterns() async throws {
    await #expect(throws: DependencyCheckError
      .unsupportedPattern("../API/**"))
    {
      try await mock.check([], allowingReferencesTo: ["../API/**"])
    }
    await #expect(throws: DependencyCheckError
      .unsupportedPattern("/Shared/**"))
    {
      try await mock.check([], from: ["/Shared/**"])
    }
  }
}
