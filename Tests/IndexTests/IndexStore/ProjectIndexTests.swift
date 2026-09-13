import BylawsIndexStore
import Testing

@Suite(
  "Project index queries",
  .enabled(
    if: IndexUnderTest.isAvailable,
    "This build wrote no index store. Build in debug first."
  ),
  .tags(.indexStore)
)
struct ProjectIndexTests {
  @Test("A direct conformer query returns only immediate conformances")
  func findsDirectConformers() async throws {
    let index = try await IndexUnderTest.index()
    let direct = Set(index.directConformers(of: "Named").map(\.symbol.name))
    #expect(direct.contains("Declaration"))
    #expect(direct.contains("SourceFile"))
    #expect(!direct.contains("Class"))
  }

  @Test("A conformer query follows the full inheritance chain")
  func findsConformersThroughARefinement() async throws {
    let index = try await IndexUnderTest.index()
    let named = index.conformers(of: "Named")
    let names = Set(named.map(\.symbol.name))

    #expect(names.isSuperset(of: ["Class", "Struct", "Function", "Property"]))
    #expect(named.count == Set(named).count)
    let notTypes = named.filter { !$0.symbol.kind.isType }
    #expect(notTypes.isEmpty)
  }

  @Test("A conformance to a standard library protocol resolves")
  func findsConformersOfAStandardProtocol() async throws {
    let index = try await IndexUnderTest.index()
    let sendable = Set(index.conformers(of: "Sendable").map(\.symbol.name))
    #expect(sendable.contains("IndexSymbol"))
    #expect(sendable.contains("SymbolRole"))
  }

  @Test("A conformance declared in an extension counts")
  func findsConformersFromExtensions() async throws {
    let index = try await IndexUnderTest.index()
    let describable = Set(
      index.conformers(of: "CustomStringConvertible").map(\.symbol.name)
    )
    #expect(describable.contains("IndexSymbol"))
    #expect(describable.contains("IndexReference"))
  }

  @Test("A reference query excludes definitions")
  func separatesReferencesFromDefinitions() async throws {
    let index = try await IndexUnderTest.index()
    let definitions = index.definitions(of: "IndexSymbol")
    let references = index.references(to: "IndexSymbol")

    #expect(!definitions.isEmpty)
    let elsewhere = definitions
      .filter { !$0.file.hasSuffix("IndexSymbol.swift") }
    #expect(elsewhere.isEmpty)
    #expect(!references.isEmpty)
    let defining = references.filter { $0.roles.contains(.definition) }
    #expect(defining.isEmpty)
  }

  @Test("A module query returns the module that defines a symbol")
  func reportsTheDefiningModule() async throws {
    let index = try await IndexUnderTest.index()
    #expect(index.modules(defining: "IndexStore") == ["BylawsIndexStore"])
    #expect(index.modules(defining: "Matcher") == ["BylawsCore"])
  }

  @Test("Queries for an unknown symbol return empty results")
  func reportsNothingForAnUnknownName() async throws {
    let index = try await IndexUnderTest.index()
    #expect(index.conformers(of: "NoSuchProtocol").isEmpty)
    #expect(index.references(to: "NoSuchSymbol").isEmpty)
  }

  @Test("An unknown requested module reports the available modules")
  func reportsAnUnknownModule() throws {
    let store = try IndexStore(path: IndexUnderTest.storePath())
    do {
      _ = try ProjectIndex(store: store, modules: ["NoSuchModule"])
      Issue.record("The index accepted an unknown module.")
    } catch {
      guard case let .missingModules(names, available) = error else {
        Issue.record("The index reported the wrong error: \(error)")
        return
      }
      #expect(names == ["NoSuchModule"])
      #expect(available.contains("BylawsIndexStore"))
    }
  }

  @Test("A C header occurrence reports the header path")
  func attributesAHeaderOccurrenceToTheHeader() throws {
    let store = try IndexStore(path: IndexUnderTest.storePath())
    let index = try ProjectIndex(store: store, modules: ["CIndexStore"])
    let definitions = index.definitions(of: "indexstore_string_ref_t")

    #expect(!definitions.isEmpty)
    #expect(definitions.allSatisfy { $0.file.hasSuffix("CIndexStore.h") })
  }
}
