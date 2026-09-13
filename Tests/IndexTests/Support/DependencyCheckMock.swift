import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics

struct DependencyCheckMock {
  let orders = "/virtual/Sources/Features/Orders/Model.swift"
  let payments = "/virtual/Sources/Features/Payments/Model.swift"
  let ordersAPI = "/virtual/Sources/Features/Orders/API/OrdersAPI.swift"
  let paymentsAPI = "/virtual/Sources/Features/Payments/API/PaymentsAPI.swift"
  let shared = "/virtual/Sources/Shared/Clock.swift"
  let outside = "/virtual/Sources/Other/Other.swift"

  func check(
    _ groups: [[IndexReference]],
    checkingCycles: Bool = false,
    between dependencyGroups: [DependencyGroup]? = nil,
    pattern: String? = "Sources/Features/*",
    from sources: [String] = ["Sources/Features/**", "Sources/Shared/**"],
    allowingReferencesTo destinations: [String] = [
      "Sources/Features/*/API/**",
      "Sources/Shared/**",
    ]
  ) async throws -> Rule.Findings {
    let codebase = Codebase(root: .sources([
      "Sources/Features/Orders/Model.swift": "struct Order {}",
      "Sources/Features/Orders/API/OrdersAPI.swift": "protocol OrdersAPI {}",
      "Sources/Features/Payments/Model.swift": "struct Payment {}",
      "Sources/Features/Payments/API/PaymentsAPI.swift": "protocol PaymentsAPI {}",
      "Sources/Shared/Clock.swift": "struct Clock {}",
      "Sources/Other/Other.swift": "struct Other {}",
    ]), including: ["Sources/**"])
    let parsed = try await CodebaseCache.shared.parsedCodebase(for: codebase)
    let plan: DependencyPlan
    if checkingCycles {
      let selected = if let dependencyGroups { dependencyGroups } else {
        try await codebase
          .dependencyGroups(inFoldersMatching: pattern ?? "Sources/Features/*")
      }
      plan = try DependencyPlan(between: selected, parsedCodebase: parsed)
    } else {
      plan = try DependencyPlan(
        from: sources, allowingReferencesTo: destinations,
        foldersMatching: pattern, parsedCodebase: parsed
      )
    }
    return DependencyAnalyser(plan: plan).check(
      occurrenceGroups: groups,
      checkingCycles: checkingCycles,
      reportedAt: .start(of: "/virtual/Bylaws.swift")
    )
  }

  func edge(
    from source: String,
    to destination: String
  ) -> [IndexReference] {
    [
      reference(file: destination, symbol: destination, roles: .definition),
      reference(file: source, symbol: destination, roles: .reference),
    ]
  }

  func reference(
    file: String,
    symbol: String,
    roles: SymbolRole,
    module: String = "App"
  ) -> IndexReference {
    IndexReference(
      symbol: IndexSymbol(usr: symbol, name: symbol, kind: .struct),
      module: module,
      file: file,
      line: 3,
      column: 5,
      roles: roles
    )
  }
}
