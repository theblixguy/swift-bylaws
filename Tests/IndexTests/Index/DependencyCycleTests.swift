import BylawsCore
import Testing

@Suite("Dependency cycles")
struct DependencyCycleTests {
  private let mock = DependencyCheckMock()

  @Test("One group can contain files from separate folders")
  func disjointPaths() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.shared),
      mock.edge(from: mock.shared, to: mock.payments),
      mock.edge(from: mock.payments, to: mock.orders),
    ], checkingCycles: true, between: [
      .init(
        "Orders",
        files: ["Sources/Features/Orders/**", "Sources/Shared/**"]
      ),
      .init("Payments", files: ["Sources/Features/Payments/**"]),
    ])

    #expect(result.violations.count == 2)
    #expect(result.violations.offenders.allSatisfy {
      $0.description == "dependency cycle: Orders -> Payments -> Orders"
    })
    #expect(result.warnings.isEmpty)
  }

  @Test("Repeated patterns within one group do not overlap")
  func repeatedPatterns() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.ordersAPI),
    ], checkingCycles: true, between: [
      .init(
        "Orders",
        files: ["Sources/Features/Orders/**", "Sources/Features/Orders/API/**"]
      ),
    ])

    #expect(result.violations.isEmpty)
    #expect(result.warnings.isEmpty)
  }

  @Test("Files cannot belong to two groups")
  func overlappingGroups() async {
    await #expect(throws: DependencyGroupError.self) {
      try await mock.check([], checkingCycles: true, between: [
        .init("Orders", files: ["Sources/Features/Orders/**"]),
        .init("Features", files: ["Sources/Features/**"]),
      ])
    }
  }

  @Test(
    "Group names must be distinct and non-empty",
    arguments: ["", " \n", "Orders"]
  )
  func groupNames(_ name: String) async {
    let expected: DependencyGroupError = name == "Orders" ?
      .duplicateName(name) : .emptyName
    await #expect(throws: expected) {
      try await mock.check([], checkingCycles: true, between: [
        .init("Orders", files: []), .init(name, files: []),
      ])
    }
  }

  @Test("Unmatched groups produce warnings")
  func unmatchedGroup() async throws {
    let result = try await mock.check([], checkingCycles: true, between: [
      .init("Missing", files: ["Missing/**"]),
    ])

    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.message.contains("'Missing'") == true)
  }

  @Test("Cycles exclude references outside the matching folders")
  func cycleScope() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.outside),
      mock.edge(from: mock.outside, to: mock.orders),
    ], checkingCycles: true, from: ["Sources/**"])
    #expect(result.violations.checkedCount == 0)
    #expect(result.violations.isEmpty)
  }

  @Test("Cycles report a source reference for each dependency")
  func cycle() async throws {
    let result = try await mock.check([
      mock.edge(from: mock.orders, to: mock.paymentsAPI),
      mock.edge(from: mock.payments, to: mock.ordersAPI),
    ], checkingCycles: true)

    #expect(result.violations.count == 2)
    #expect(result.violations.offenders.map(\.description) == Array(
      repeating:
      "dependency cycle: Sources/Features/Orders -> Sources/Features/Payments -> Sources/Features/Orders",
      count: 2
    ))
  }

  @Test("Missing index data produces folder warnings")
  func missingIndexData() async throws {
    let result = try await mock.check([], checkingCycles: true)

    #expect(result.warnings.count == 2)
    #expect(result.warnings
      .allSatisfy {
        $0.message.contains("has no indexed declarations or references")
      })
  }

  @Test("Unmatched folder pattern produces a warning")
  func unmatchedPattern() async throws {
    let result = try await mock.check(
      [],
      checkingCycles: true,
      pattern: "Sources/Missing/*"
    )

    #expect(result.warnings.count == 1)
    #expect(result.warnings.first?.message
      .contains("has no groups") == true)
  }

  @Test("Index record order does not change the reported cycle")
  func cycleOrder() async throws {
    let edges = [
      mock.edge(from: mock.orders, to: mock.paymentsAPI),
      mock.edge(from: mock.payments, to: mock.ordersAPI),
    ]

    let forward = try await mock.check(edges, checkingCycles: true)
    let reverse = try await mock.check(
      edges.reversed().map { Array($0.reversed()) },
      checkingCycles: true
    )

    #expect(forward.violations == reverse.violations)
  }
}
