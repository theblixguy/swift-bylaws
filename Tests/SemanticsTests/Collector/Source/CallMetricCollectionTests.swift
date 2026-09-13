import BylawsSemantics
import Testing

@Suite("Call metric collection")
struct CallMetricCollectionTests {
  @Test("Collector counts await expressions in declaration bodies")
  func countsAwaits() throws {
    let file = try FileCollector.collect(
      source: """
      struct Loader {
        func load() async {
          await first()
          let value = await second()
          print(value)
        }
        func idle() async {}
      }
      """,
      path: "/virtual/App/Awaits.swift"
    )

    let load = try #require(file.functions.first { $0.name == "load" })
    #expect(load.awaitCount == 2)

    let idle = try #require(file.functions.first { $0.name == "idle" })
    #expect(idle.awaitCount == 0)
  }

  @Test("Collector records calls in a property initialiser")
  func extractsPropertyInitializerCalls() throws {
    let file = try FileCollector.collect(
      source: """
      struct Preferences {
        static let defaults = UserDefaults(suiteName: "app")
        let plain = 1
      }
      let package = Package(name: "App")
      """,
      path: "/virtual/App/Defaults.swift"
    )

    let defaults = try #require(
      file.properties.first { $0.name == "defaults" }
    )
    #expect(defaults.calls("UserDefaults"))
    let firstCall = try #require(defaults.calls.first)
    #expect(firstCall.hasArgumentLabel("suiteName"))

    let plain = try #require(file.properties.first { $0.name == "plain" })
    #expect(plain.calls.isEmpty)

    let package = try #require(
      file.properties.first { $0.name == "package" }
    )
    #expect(package.calls("Package"))
    #expect(file.calls("Package"))
  }

  @Test("A dotted call path matches neighbouring parts only")
  func matchesDottedCallPaths() throws {
    let file = try FileCollector.collect(
      source: """
      struct Loader {
        func load() {
          Task.detached { }
          UserDefaults.standard.set(true, forKey: "seen")
        }
        func wait() async {
          let clock = ContinuousClock()
          try? await clock.sleep(for: .seconds(1))
        }
      }
      """,
      path: "/virtual/App/Loader.swift"
    )

    let load = try #require(file.functions.first { $0.name == "load" })
    #expect(load.calls("Task.detached"))
    #expect(load.calls("UserDefaults.standard.set"))
    #expect(load.calls("standard"))
    #expect(!load.calls("clock.sleep"))

    let wait = try #require(file.functions.first { $0.name == "wait" })
    #expect(wait.calls("clock.sleep"))
    #expect(!wait.calls("Task.detached"))

    let detached = try #require(load.calls.first)
    #expect(detached.baseName == "Task")
    #expect(detached.memberName == "detached")
  }

  @Test("Collector assigns a declaration macro call to its file")
  func recordsDeclarationMacros() throws {
    let file = try FileCollector.collect(
      source: """
      struct HomeView {}

      #Preview("Home") {
        HomeView()
      }
      """,
      path: "/virtual/App/HomeView.swift"
    )

    #expect(file.macroExpansions.map(\.name) == ["#Preview"])
    #expect(file.calls("#Preview"))
    #expect(file.macroExpansions.first?.location.line == 3)
  }
}
