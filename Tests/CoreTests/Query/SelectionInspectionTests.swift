import BylawsCore
import BylawsSemantics
import Testing

@Suite("Selection inspection")
struct SelectionInspectionTests {
  @Test("Each filter records retained and removed declarations")
  func filters() async throws {
    let app = Codebase(root: .sources([
      "Sources/OrderView.swift": "final class OrderView {}\nclass OrderModel {}",
      "Tests/OrderViewTests.swift": "class OrderViewTests {}",
    ]), including: ["**"])
    let rule = Rule("views", "Views are final") {
      Violations(
        of: .isFinal,
        in: try await app.classes.under("Sources").suffixed("View")
      )
    }

    let inspection = try await rule.inspect()

    #expect(inspection.findings.violations.isEmpty)
    #expect(inspection.selections.map(\.selected.count) == [3, 2, 1])
    #expect(inspection.selections.map(\.excluded.count) == [0, 1, 1])
    #expect(inspection.selections.last?.selected.map(\.name) == ["OrderView"])
    #expect(inspection.selections.last?.excluded.map(\.name) == ["OrderModel"])
  }

  @Test("Concurrent inspections keep separate selections")
  func concurrentRules() async throws {
    let app =
      Codebase(
        root: .sources(
          ["Sources/App.swift": "class Order {}\nstruct Payment {}"]
        )
      )
    let classes = Rule("classes", "Classes are final") {
      Violations(of: .isFinal, in: try await app.classes)
    }
    let structs = Rule("structs", "Structs are public") {
      Violations(of: .isPublic, in: try await app.structs)
    }

    async let classInspection = classes.inspect()
    async let structInspection = structs.inspect()
    let (classResult, structResult) = try await (
      classInspection,
      structInspection
    )

    #expect(classResult.selections.flatMap(\.selected).map(\.name) == ["Order"])
    #expect(structResult.selections.flatMap(\.selected)
      .map(\.name) == ["Payment"])
  }

  @Test("Disabled inspection does not describe elements")
  func disabledInspection() {
    QueryInspection.record(query: "unused", selected: {
      Issue
        .record("Element descriptions must not be computed outside inspection")
      return []
    }())
  }

  @Test("Cached projections remain visible on repeated inspections")
  func cachedSelection() async throws {
    let app =
      Codebase(root: .sources(["Sources/App.swift": "final class Order {}"]))
    let rule = Rule("final", "Classes are final") {
      Violations(of: .isFinal, in: try await app.classes)
    }

    let first = try await rule.inspect()
    let second = try await rule.inspect()

    #expect(!first.selections.isEmpty)
    #expect(first.selections == second.selections)
  }
}
