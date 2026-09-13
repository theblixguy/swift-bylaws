import Bylaws
import Testing

@Suite("Cookbook patterns")
struct CookbookPatternTests {
  @Test("A path filter excludes a directory")
  func filtersOutsideADirectory() async throws {
    let printing = try await codebase.functions
      .outside("Sources/Logging")
      .where(.calls("print"))
    #expect(printing.map(\.name) == ["load"])

    let everywhere = try await codebase.functions.where(.calls("print"))
    #expect(everywhere.count == 2)
  }

  @Test("A dotted call path bans one member of a type")
  func bansOneMember() async throws {
    let violations = try await codebase.functions
      .violations(matching: .calls("Task.detached"))
    #expect(violations.count == 1)
    #expect(violations.offenders.first?.name == "load")
  }

  @Test("A call query matches a dotted path with its labels")
  func matchesCallSignatures() async throws {
    let detached = try await codebase.calls
      .where(.references("Task.detached"))
    #expect(detached.count == 1)

    let missing = try await codebase.calls
      .where(.references("Task.sleep"))
    #expect(missing.isEmpty)
  }

  @Test("A declaration macro matches on the file")
  func matchesPreviewMacro() async throws {
    let withPreviews = try await codebase.files
      .where(.calls("#Preview"))
    #expect(withPreviews.map(\.name) == ["HomeView.swift"])
  }

  @Test("A missing super call identifies the override as a violation")
  func findsOverridesWithoutSuper() async throws {
    let overrides = Codebase(root: .sources([
      "Sources/UI/Screen.swift": """
      final class Screen: UIViewController {
        override func viewDidLoad() {
          super.viewDidLoad()
        }
        override func viewWillAppear(_ animated: Bool) {
          setUp()
        }
      }
      """,
    ]))
    let lifecycle = try await overrides.functions
      .named("viewDidLoad", "viewWillAppear")
      .where(.isOverride)
    let missing = lifecycle.filter { !$0.calls("super.\($0.name)") }
    #expect(missing.map(\.name) == ["viewWillAppear"])
  }

  @Test("A missing generic constraint identifies the function as a violation")
  func findsUnconstrainedGenerics() async throws {
    let generics = Codebase(root: .sources([
      "Sources/App/Store.swift": """
      public func save<Model: Codable>(_ model: Model) {}
      public func load<Value>(_ key: String) -> Value? { nil }
      """,
    ]))
    let unconstrainedFunctions = try await generics.functions.where(.isPublic)
      .filter { $0.genericParameters.contains { $0.constraintName == nil } }
    #expect(unconstrainedFunctions.map(\.name) == ["load"])
  }

  @Test("Initializer queries return a separate selection")
  func queriesInitializers() async throws {
    let types = Codebase(root: .sources([
      "Sources/App/Loader.swift": """
      final class Loader {
        init() {}
        convenience init(name: String) { self.init() }
      }
      """,
    ]))
    let convenience = try await types.initializers.where(.isConvenience)
    #expect(convenience.count == 1)
    #expect(try await types.initializers.count == 2)
  }

  @Test("A dictionary reports its key type")
  func readsDictionaryKeyType() async throws {
    let models = Codebase(root: .sources([
      "Sources/Domain/Index.swift": """
      struct Index {
        var byIdentifier: [OrderID: Order] = [:]
        var byName: [String: Order] = [:]
      }
      """,
    ]))
    let rawKeys = try await models.properties.filter { property in
      guard let key = property.type?.keyType else { return false }
      return ["String", "Int", "UUID"].contains(key.name)
    }
    #expect(rawKeys.map(\.name) == ["byName"])
  }

  @Test("Non-private view state identifies the property as a violation")
  func findsExposedViewState() async throws {
    let views = try await codebase.structs.where(.conforms(to: "View"))
    let view = try #require(views.first)
    let exposed = view.properties
      .filter { $0.hasAttribute("State") || $0.hasAttribute("StateObject") }
      .filter { $0.visibility > .private }
    #expect(exposed.map(\.name) == ["isOpen"])
  }

  @Test("A file query returns top-level types without nested types")
  func findsTopLevelTypes() async throws {
    let files = try await codebase.files.named("HomeView.swift")
    let file = try #require(files.first)
    let topLevel = file.structs.filter { $0.enclosingTypeName == nil }
      .map(\.name)
      + file.classes.filter { $0.enclosingTypeName == nil }.map(\.name)
      + file.enums.filter { $0.enclosingTypeName == nil }.map(\.name)
    #expect(topLevel == ["HomeView"])
    #expect(file.name == "\(try #require(topLevel.first)).swift")
  }

  @Test("One rule covers every kind of type")
  func checksEveryKindOfType() async throws {
    let models = Codebase(root: .sources([
      "Sources/Models/Cart.swift": """
      /// A cart.
      public struct Cart {}
      /// A cart line.
      public enum CartLine { case item }
      public final class CartStore {}
      """,
    ]))

    let documented = try await models.types.where(\.isPublic)
    #expect(documented.count == 3)
    #expect(documented.filter(\.isDocumented).count == 2)

    let valueTypes = try await models.types.under("Sources/Models")
    let violations = valueTypes.violations(of: .isStruct || .isEnum)
    #expect(violations.count == 1)
    #expect(violations.offenders.first?.name == "CartStore")
  }

  @Test("A test with no assertion is a violation")
  func findsTestsWithoutAssertions() async throws {
    let tests = Codebase(root: .sources([
      "Tests/AppTests/HomeTests.swift": """
      struct HomeTests {
        @Test func opens() {
          #expect(1 == 1)
        }
        @Test func closes() {
          let value = 1
          _ = value
        }
      }
      """,
    ]))
    let cases = try await tests.functions.where(.hasAttribute("Test"))
    let silent = cases.filter { !$0.calls("#expect") && !$0.calls("#require") }
    #expect(silent.map(\.name) == ["closes"])
  }

  private let codebase = Codebase(root: .sources([
    "Sources/Logging/Log.swift": """
    enum Log {
      static func write(_ message: String) { print(message) }
    }
    """,
    "Sources/Feature/HomeView.swift": """
    struct HomeView: View {
      @State var isOpen = false
      @State private var count = 0
      var body: some View { Text("hi") }
    }

    #Preview {
      HomeView()
    }
    """,
    "Sources/Feature/Loader.swift": """
    struct Loader {
      func load() {
        print("loading")
        Task.detached { }
      }
    }
    """,
  ]))
}
