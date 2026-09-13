import Bylaws
import Testing

@Suite("Written-type matchers")
struct TypeMatcherTests {
  @Test("A written optional type matches and an inferred type is nil")
  func matchesOptionalProperties() async throws {
    let optionals = try await codebase.properties
      .where(.hasOptionalType)
    #expect(optionals.map(\.name) == ["discount"])

    let inferred = try #require(
      try await codebase.properties.named("inferred").first
    )
    #expect(inferred.type == nil)
  }

  @Test("A type matcher expands collection shorthand")
  func matchesTypeNames() async throws {
    let arrays = try await codebase.properties.where(.hasType("Array"))
    #expect(arrays.map(\.name) == ["lines"])

    let dictionaries = try await codebase.properties
      .where(.hasType("Dictionary"))
    #expect(dictionaries.map(\.name) == ["index"])

    let strings = try await codebase.properties.where(.hasType("String"))
    #expect(strings.map(\.name) == ["identifier"])
  }

  @Test("A reference matcher finds a nested generic argument")
  func matchesNestedReferences() async throws {
    let referring = try await codebase.properties
      .where(.referencesType("OrderLine"))
    #expect(referring.map(\.name) == ["lines", "index"])
  }

  @Test("A function matcher checks return and parameter types")
  func matchesFunctionTypes() async throws {
    let optionalReturns = try await codebase.functions
      .where(.returnsOptional)
    #expect(optionalReturns.map(\.name) == ["voucher"])

    let takingDiscounts = try await codebase.functions
      .where(.hasParameter(referencing: "Discount"))
    #expect(takingDiscounts.map(\.name) == ["apply"])
  }

  private let codebase = Codebase(root: .sources([
    "Sources/App/Order.swift": """
    struct Order {
      let identifier: String
      var discount: Discount?
      var lines: [OrderLine] = []
      var index: [String: OrderLine] = [:]
      var inferred = 0
      func total() -> Money { Money() }
      func voucher() -> Voucher? { nil }
      func apply(_ discounts: [Discount], to order: Order) {}
    }
    """,
  ]))
}
