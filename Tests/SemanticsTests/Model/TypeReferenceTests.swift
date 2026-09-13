import BylawsSemantics
import Testing

@Suite("Written-type parsing")
struct TypeReferenceTests {
  @Test(
    "A plain type reports its name",
    arguments: [
      ("Order", "Order"),
      ("Swift.String", "String"),
      ("Outer.Inner", "Inner"),
      ("  Order  ", "Order"),
    ]
  )
  func plainTypes(written: String, name: String) {
    let type = TypeReference(written)
    #expect(type.name == name)
    #expect(!type.isOptional)
    #expect(type.genericArguments.isEmpty)
  }

  @Test(
    "An optional reports the wrapped type",
    arguments: [
      "Order?",
      "Order!",
      "Optional<Order>",
    ]
  )
  func optionals(written: String) {
    let type = TypeReference(written)
    #expect(type.isOptional)
    #expect(type.name == "Order")
    #expect(type.text == written)
  }

  @Test("Parser expands array shorthand")
  func arrayShorthand() throws {
    let type = TypeReference("[Order]")
    #expect(type.isArray)
    #expect(type.name == "Array")
    #expect(try #require(type.elementType).name == "Order")
    #expect(TypeReference("Array<Order>").isArray)
  }

  @Test("Parser expands dictionary shorthand to a key and a value")
  func dictionaryShorthand() throws {
    let type = TypeReference("[String: [Order]]")
    #expect(type.isDictionary)
    #expect(try #require(type.keyType).name == "String")
    let value = try #require(type.valueType)
    #expect(value.isArray)
    #expect(try #require(value.elementType).name == "Order")
    #expect(type.elementType == nil)
  }

  @Test(
    "An optional collection reports both optional and collection properties"
  )
  func optionalCollection() throws {
    let type = TypeReference("[Order]?")
    #expect(type.isOptional)
    #expect(type.isArray)
    #expect(try #require(type.elementType).name == "Order")
  }

  @Test("Parser returns generic arguments in source order")
  func genericArguments() {
    let type = TypeReference("Result<Order, any Error>")
    #expect(type.name == "Result")
    #expect(type.genericArguments.map(\.name) == ["Order", "Error"])
    #expect(type.genericArguments.last?.isExistential == true)
  }

  @Test("Existential and opaque types report their constraint")
  func existentialAndOpaque() {
    let existential = TypeReference("any UserRepository")
    #expect(existential.isExistential)
    #expect(existential.name == "UserRepository")

    let opaque = TypeReference("some View")
    #expect(opaque.isOpaque)
    #expect(opaque.name == "View")
    #expect(!opaque.isExistential)
  }

  @Test(
    "Parser identifies a function type inside parentheses",
    arguments: [
      "() -> Void",
      "(Int) -> String",
      "@escaping (Int) async throws -> String",
    ]
  )
  func functionTypes(written: String) {
    let type = TypeReference(written)
    #expect(type.isFunction)
    #expect(!type.isTuple)
  }

  @Test("A parenthesised type is a tuple only with more than one element")
  func tuples() {
    #expect(TypeReference("(Int, String)").isTuple)
    #expect(TypeReference("(name: String, age: Int)").isTuple)

    let parenthesised = TypeReference("(Order)")
    #expect(!parenthesised.isTuple)
    #expect(parenthesised.name == "Order")
  }

  @Test("A tuple that contains a function is still a tuple")
  func tupleHoldingFunction() {
    let type = TypeReference("((Int) -> Void, Int)")
    #expect(type.isTuple)
    #expect(!type.isFunction)
  }

  @Test(
    "A parameter modifier or attribute does not change the type",
    arguments: [
      "inout Order",
      "borrowing Order",
      "@Sendable Order",
    ]
  )
  func modifiersAndAttributes(written: String) {
    #expect(TypeReference(written).name == "Order")
  }

  @Test("A protocol composition uses its source text as the name")
  func composition() {
    let type = TypeReference("any Codable & Sendable")
    #expect(type.isExistential)
    #expect(type.name == "Codable & Sendable")
  }

  @Test("A nested generic argument counts as a reference")
  func nestedReferences() {
    let type = TypeReference("[String: Result<Order, Error>]")
    #expect(type.references("Order"))
    #expect(type.references("Dictionary"))
    #expect(type.references("Result"))
    #expect(!type.references("Invoice"))
  }

  @Test("Parser accepts an empty type annotation")
  func emptyText() {
    #expect(TypeReference("").name.isEmpty)
  }

  @Test("An optional return type does not make the function optional")
  func optionalReturnType() {
    let returningOptional = TypeReference("(Int) -> String?")
    #expect(returningOptional.isFunction)
    #expect(!returningOptional.isOptional)

    let optionalFunction = TypeReference("((Int) -> String)?")
    #expect(optionalFunction.isFunction)
    #expect(optionalFunction.isOptional)
  }

  @Test("Parser identifies parenthesised dictionary and function types")
  func nestedColonKeepsTheType() throws {
    let dictionary = TypeReference("([String: Int])")
    #expect(!dictionary.isTuple)
    #expect(dictionary.isDictionary)
    #expect(try #require(dictionary.keyType).name == "String")

    let function = TypeReference("((String, [String: Int]) -> Void)")
    #expect(function.isFunction)
    #expect(!function.isTuple)
  }

  @Test("A qualified generic reports the last name without its clause")
  func qualifiedGenerics() {
    #expect(TypeReference("Array<Int>.Element").name == "Element")
    #expect(TypeReference("Foo<A>.Bar<B>").name == "Bar")
  }

  @Test("Parser removes stacked parameter modifiers")
  func stackedModifiers() {
    #expect(TypeReference("isolated borrowing Foo").name == "Foo")
    #expect(TypeReference("inout [Int]?").isArray)
  }

  @Test(
    "Parser returns a non-empty name for malformed text",
    arguments: [
      "<>",
      "[",
      "A<",
      "(",
      "()",
      ">",
    ]
  )
  func malformedText(written: String) {
    let type = TypeReference(written)
    #expect(!type.name.isEmpty)
    #expect(type.text == written)
  }
}
