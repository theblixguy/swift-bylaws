import BylawsSemantics
import Testing

@Suite("Call collection")
struct CallCollectionTests {
  @Test("Collector records call argument labels")
  func extractsArgumentLabels() throws {
    let file = try FileCollector.collect(
      source: """
      struct IconFactory {
        func icon() -> UIImage? {
          UIImage(named: "logo")
        }
      }
      """,
      path: "/virtual/App/IconFactory.swift"
    )

    let call = try #require(file.calls.first)
    #expect(call.argumentLabels == ["named"])
    #expect(call.hasArgumentLabel("named"))
    #expect(!call.hasArgumentLabel("systemName"))
  }

  @Test("Collector records call argument labels and expression text")
  func extractsCallArguments() throws {
    let file = try FileCollector.collect(
      source: """
      func crash() {
        fatalError()
      }
      func remember() {
        UserDefaults.standard.set(true, forKey: "seen")
      }
      """,
      path: "/virtual/App/Calls.swift"
    )

    let withoutArguments = try #require(
      file.calls.first { $0.references("fatalError") }
    )
    #expect(withoutArguments.arguments.isEmpty)

    let set = try #require(file.calls.first { $0.references("UserDefaults") })
    let labels = set.arguments.map(\.label)
    let texts = set.arguments.map(\.text)
    #expect(labels == [nil, "forKey"])
    #expect(texts == ["true", "\"seen\""])
  }

  @Test("Collector records attribute arguments")
  func extractsAttributeArguments() throws {
    let file = try FileCollector.collect(
      source: """
      @Suite(.serialized)
      struct LegacySuite {
        @Test("Adds one item", .tags(.shoppingCart))
        func addsItem() {}

        @Test
        func undescribed() {}
      }
      """,
      path: "/virtual/Tests/LegacySuite.swift"
    )

    let suite = try #require(file.structs.first)
    #expect(suite.attribute(named: "Suite")?.arguments == ".serialized")

    let described = try #require(file.functions.first { $0.name == "addsItem" })
    let testAttribute = try #require(described.attribute(named: "Test"))
    #expect(
      testAttribute.arguments == "\"Adds one item\", .tags(.shoppingCart)"
    )

    let undescribed = try #require(
      file.functions.first { $0.name == "undescribed" }
    )
    #expect(undescribed.attribute(named: "Test")?.arguments == nil)
  }

  @Test("Collector records macro expansions as calls")
  func extractsMacroCalls() throws {
    let file = try FileCollector.collect(
      source: """
      struct Checks {
        func verify(value: Int) throws {
          #expect(value == 1)
          let unwrapped = try #require(Optional(value))
          _ = unwrapped
        }
      }
      """,
      path: "/virtual/Tests/Checks.swift"
    )

    let verify = try #require(file.functions.first)
    #expect(verify.calls("#expect"))
    #expect(verify.calls("#require"))
  }

  @Test("Collector skips deinit and subscript bodies")
  func skipsDeinitAndSubscriptBodies() throws {
    let file = try FileCollector.collect(
      source: """
      class Container {
          deinit {
              let cleanupFlag = true
              func helperInDeinit() {}
              _ = cleanupFlag
          }
          subscript(index: Int) -> Int {
              let local = index
              return local
          }
      }
      """,
      path: "/virtual/App/Container.swift"
    )

    #expect(file.properties.isEmpty)
    #expect(file.functions.isEmpty)
  }

  @Test("Collector records call expressions from function bodies")
  func extractsCalls() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
          func save() {
              UserDefaults.standard.set(true, forKey: "seen")
              log("saved")
          }
      }
      """,
      path: "/virtual/App/Store.swift"
    )

    let save = try #require(file.functions.first)
    #expect(save.calls.map(\.calledExpression) == [
      "UserDefaults.standard.set",
      "log",
    ])
    #expect(save.calls("UserDefaults"))
    #expect(save.calls("log"))
    #expect(!save.calls("Analytics"))

    let call = try #require(save.calls.first)
    #expect(call.baseName == "UserDefaults")
    #expect(call.references("standard"))
    #expect(file.calls("UserDefaults"))
  }

  @Test("Collector skips declarations inside function bodies")
  func skipsFunctionBodies() throws {
    let file = try FileCollector.collect(
      source: """
      func outer() {
          let local = 1
          func nested() {}
      }
      """,
      path: "/virtual/App/Bodies.swift"
    )

    #expect(file.functions.map(\.name) == ["outer"])
    #expect(file.properties.isEmpty)
  }

  @Test("Outer metrics skip nested declaration bodies")
  func outerMetricsSkipNestedDeclarations() throws {
    let file = try FileCollector.collect(
      source: """
      func outer() {
        func nested() async {
          sink()
          await work()
        }
        struct Local {
          func run() { anotherSink() }
        }
      }
      """,
      path: "/virtual/App/NestedBodies.swift"
    )

    let outer = try #require(file.functions.first)
    #expect(outer.calls.isEmpty)
    #expect(outer.awaitCount == 0)
  }
}
