import BylawsCore
import BylawsSemantics
import Testing

@Suite("Name filter plans")
struct NameFilterPlanTests {
  @Test("Fused filters preserve order and descriptions", arguments: [
    [NameFilter](),
    [.prefixed(["Order", "Payment"]), .suffixed(["View"])],
    [
      .named(["OrderView", "OrderView", "PaymentView"]),
      .excluding(["OrderView"]),
    ],
    [.named([])],
    [.excluding([])],
    [.prefixed([""]), .suffixed([""])],
    [.prefixed(["订单"]), .suffixed(["视图"])],
  ])
  func equivalence(filters: [NameFilter]) async throws {
    let app = Codebase(root: .sources([
      "Sources/App.swift": """
      class OrderModel {}
      class PaymentView {}
      class OrderView {}
      class 订单视图 {}
      """,
    ]))
    let selection = try await app.classes
    let expected = filters.reduce(selection) { selection, filter in
      switch filter {
      case let .named(values): selection.named(values)
      case let .suffixed(values): selection.suffixed(values)
      case let .prefixed(values): selection.prefixed(values)
      case let .excluding(values): selection.excluding(values)
      }
    }

    let actual = selection.filtering(filters)

    #expect(actual.map(\.name) == expected.map(\.name))
    #expect(actual.queryDescription == expected.queryDescription)
  }

  @Test("Inspection preserves each filter step")
  func inspection() async throws {
    let app = Codebase(root: .sources([
      "Sources/App.swift": "class OrderView {}\nclass OrderModel {}\nclass Other {}",
    ]))
    let fused = Rule("fused", "Views are final") {
      Violations(of: .isFinal, in: try await app.classes.filtering([
        .prefixed(["Order"]), .suffixed(["View"]), .excluding(["Missing"]),
      ]))
    }
    let original = Rule("original", "Views are final") {
      Violations(
        of: .isFinal,
        in: try await app.classes
          .prefixed("Order").suffixed("View").excluding("Missing")
      )
    }

    let actual = try await fused.inspect()
    let expected = try await original.inspect()

    #expect(actual.selections == expected.selections)
    #expect(actual.selections.map(\.selected.count) == [3, 2, 1, 1])
  }
}
