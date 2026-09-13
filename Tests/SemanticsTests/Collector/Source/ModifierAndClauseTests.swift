import BylawsSemantics
import Testing

@Suite("Modifier and clause extraction")
struct ModifierAndClauseTests {
  @Test(
    "Collector records indirect, lazy, dynamic, mutating and convenience modifiers"
  )
  func extractsExtraModifiers() throws {
    let file = try FileCollector.collect(
      source: """
      indirect enum Expression {
        case literal(Int)
        indirect case sum(Expression, Expression)
      }
      struct Counter {
        lazy var cache: [Int] = []
        dynamic var observed = 0
        mutating func bump() {}
      }
      class Loader {
        init() {}
        convenience init(name: String) { self.init() }
      }
      """,
      path: "/virtual/App/Modifiers.swift"
    )

    let expression = try #require(file.enums.first)
    #expect(expression.isIndirect)
    #expect(expression.cases.map(\.isIndirect) == [false, true])

    let cache = try #require(file.properties.first { $0.name == "cache" })
    #expect(cache.isLazy)
    let observed = try #require(
      file.properties.first { $0.name == "observed" }
    )
    #expect(observed.isDynamic)

    let bump = try #require(file.functions.first { $0.name == "bump" })
    #expect(bump.isMutating)

    let convenience = try #require(
      file.initializers.first { $0.isConvenience }
    )
    #expect(convenience.parameters.count == 1)
  }

  @Test("Collector records nonisolated and nonisolated(unsafe)")
  func extractsNonisolated() throws {
    let file = try FileCollector.collect(
      source: """
      nonisolated struct Formatting {
        nonisolated(unsafe) static var cache: [String] = []
        nonisolated static let limit = 3
        nonisolated func format() {}
      }
      """,
      path: "/virtual/App/Formatting.swift"
    )

    let formatting = try #require(file.structs.first)
    #expect(formatting.isNonisolated)

    let cache = try #require(file.properties.first { $0.name == "cache" })
    #expect(cache.isNonisolated)
    #expect(cache.isNonisolatedUnsafe)

    let limit = try #require(file.properties.first { $0.name == "limit" })
    #expect(limit.isNonisolated)
    #expect(!limit.isNonisolatedUnsafe)

    let format = try #require(file.functions.first)
    #expect(format.isNonisolated)
  }

  @Test("An attributed inheritance entry matches by its type name")
  func attributedInheritanceMatches() throws {
    let file = try FileCollector.collect(
      source: """
      final class Registry: @unchecked Sendable {}
      """,
      path: "/virtual/App/Registry.swift"
    )

    let registry = try #require(file.classes.first)
    #expect(registry.directlyConforms(to: "Sendable"))
    #expect(registry.inheritedTypes == ["@unchecked Sendable"])
  }

  @Test("Collector records effect specifiers on functions and initialisers")
  func extractsEffectSpecifiers() throws {
    let file = try FileCollector.collect(
      source: """
      struct Loader {
        init(path: String) throws {}
        func fetch() async throws -> Int { 1 }
        func map(_ transform: () throws -> Void) rethrows {}
        func plain() {}
      }
      """,
      path: "/virtual/App/Loader.swift"
    )

    let fetch = try #require(file.functions.first { $0.name == "fetch" })
    #expect(fetch.isAsync)
    #expect(fetch.isThrowing)

    let map = try #require(file.functions.first { $0.name == "map" })
    #expect(map.isThrowing)
    #expect(!map.isAsync)

    let plain = try #require(file.functions.first { $0.name == "plain" })
    #expect(!plain.isAsync)
    #expect(!plain.isThrowing)

    let initializer = try #require(file.initializers.first)
    #expect(initializer.isThrowing)
    #expect(!initializer.isAsync)
  }

  @Test(
    "A protocol records its requirements without nested implementation members"
  )
  func extractsProtocolRequirements() throws {
    let file = try FileCollector.collect(
      source: """
      protocol UserRepository {
        var isReady: Bool { get }
        func user(for id: String) async throws -> String
        func reset()
      }
      """,
      path: "/virtual/App/UserRepository.swift"
    )

    let repository = try #require(file.protocols.first)
    #expect(repository.requiredFunctions.map(\.name) == ["user", "reset"])
    #expect(repository.requiredProperties.map(\.name) == ["isReady"])
    let user = try #require(repository.requiredFunctions.first)
    #expect(user.isAsync)
    #expect(user.enclosingTypeName == "UserRepository")

    #expect(file.functions.isEmpty)
    #expect(file.properties.isEmpty)
  }

  @Test("A setter-scoped modifier does not change declaration visibility")
  func setterScopedModifierKeepsVisibility() throws {
    let file = try FileCollector.collect(
      source: """
      public struct Counter {
        public private(set) var count = 0
        internal(set) var total = 0
      }
      """,
      path: "/virtual/App/Counter.swift"
    )

    let count = try #require(file.properties.first { $0.name == "count" })
    #expect(count.visibility == .public)
    let total = try #require(file.properties.first { $0.name == "total" })
    #expect(total.visibility == .internal)
  }

  @Test("Collector records generic parameter names and constraints")
  func extractsGenericParameters() throws {
    let file = try FileCollector.collect(
      source: """
      struct Box<Value: Codable, Tag> {}
      func decode<T: Decodable>(_ data: Data) -> T? { nil }
      """,
      path: "/virtual/App/Generics.swift"
    )

    let box = try #require(file.structs.first)
    #expect(box.genericParameters.map(\.name) == ["Value", "Tag"])
    #expect(
      box.genericParameters.map(\.constraintName) == ["Codable", nil]
    )

    let decode = try #require(file.functions.first)
    #expect(decode.genericParameters.map(\.name) == ["T"])
    #expect(decode.genericParameters.first?.constraintName == "Decodable")
  }
}
