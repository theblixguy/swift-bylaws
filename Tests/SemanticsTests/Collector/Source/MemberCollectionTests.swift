import BylawsSemantics
import Testing

@Suite("Member collection")
struct MemberCollectionTests {
  @Test("Collector assigns members to their declaring type")
  func attachesMembers() throws {
    let file = try FileCollector.collect(
      source: """
      struct Outer {
          var value = 0
          struct Inner {
              var nested = 1
          }
      }
      """,
      path: "/virtual/App/Nesting.swift"
    )

    let outer = try #require(file.structs.first { $0.name == "Outer" })
    #expect(outer.properties.map(\.name) == ["value"])

    let inner = try #require(file.structs.first { $0.name == "Inner" })
    #expect(inner.qualifiedName == "Outer.Inner")
    #expect(inner.properties.map(\.name) == ["nested"])
  }

  @Test("Collector assigns extension members to the extended type")
  func attachesExtensionMembers() throws {
    let file = try FileCollector.collect(
      source: """
      extension Store: Titled {
          func reload() {}
      }
      """,
      path: "/virtual/App/Store+Titled.swift"
    )

    let anExtension = try #require(file.extensions.first)
    #expect(anExtension.extendedTypeName == "Store")
    #expect(anExtension.inheritedTypes == ["Titled"])

    let reload = try #require(file.functions.first)
    #expect(reload.enclosingTypeName == "Store")
  }

  @Test("Members from a same-file extension share the nominal member view")
  func combinesDeclarationAndExtensionMembers() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
        func load() {}
      }

      extension Store {
        func reload() {}
      }
      """,
      path: "/virtual/App/Store.swift"
    )

    let store = try #require(file.structs.first)
    #expect(store.functions.map(\.name) == ["load", "reload"])
    #expect(file.functions.map(\.name) == ["load", "reload"])
  }

  @Test("Collector records actors with their members")
  func extractsActors() throws {
    let file = try FileCollector.collect(
      source: """
      actor SessionStore: Sendable {
          var startCount = 0
          func begin() { log() }
      }
      """,
      path: "/virtual/App/SessionStore.swift"
    )

    let store = try #require(file.actors.first)
    #expect(store.name == "SessionStore")
    #expect(store.inherits(from: "Sendable"))
    #expect(store.properties.map(\.name) == ["startCount"])
    #expect(store.functions.map(\.name) == ["begin"])

    let begin = try #require(file.functions.first)
    #expect(begin.enclosingTypeName == "SessionStore")
    #expect(begin.calls("log"))
  }

  @Test("Collector records ownership and override modifiers")
  func extractsOwnershipAndOverride() throws {
    let file = try FileCollector.collect(
      source: """
      class DetailViewController: UIViewController {
        weak var delegate: DetailDelegate?
        unowned var coordinator: Coordinator

        override func viewDidLoad() {
          super.viewDidLoad()
        }
      }
      """,
      path: "/virtual/App/DetailViewController.swift"
    )

    let delegate = try #require(file.properties.first { $0.name == "delegate" })
    #expect(delegate.isWeak)
    #expect(delegate.ownership == .weak)

    let coordinator = try #require(
      file.properties.first { $0.name == "coordinator" }
    )
    #expect(coordinator.ownership == .unowned)
    #expect(!coordinator.isWeak)

    let viewDidLoad = try #require(file.functions.first)
    #expect(viewDidLoad.isOverride)
    #expect(viewDidLoad.calls("super"))
  }

  @Test("Collector records enum case raw values")
  func extractsEnumCaseRawValues() throws {
    let file = try FileCollector.collect(
      source: """
      enum Route: String, Codable {
        case home = "home"
        case settings
      }
      """,
      path: "/virtual/App/Route.swift"
    )

    let route = try #require(file.enums.first)
    let home = try #require(route.cases.first)
    let settings = try #require(route.cases.last)
    #expect(home.rawValue == "\"home\"")
    #expect(settings.rawValue == nil)
  }

  @Test("Collector records enum case documentation")
  func extractsEnumCaseDocumentation() throws {
    let file = try FileCollector.collect(
      source: """
      enum Route {
        /// Opens the home screen.
        case home
        case settings
      }
      """,
      path: "/virtual/App/Route.swift"
    )

    let route = try #require(file.enums.first)
    let home = try #require(route.cases.first)
    let settings = try #require(route.cases.last)
    #expect(home.documentation == "/// Opens the home screen.")
    #expect(settings.documentation == nil)
  }
}
