import BylawsIndexStore
import Testing

@Suite(
  "Analyser rule examples",
  .enabled(
    if: IndexUnderTest.isAvailable,
    "This build wrote no index store. Build in debug first."
  ),
  .tags(.indexStore)
)
struct AnalyserExampleTests {
  @Test(
    "Index queries return references and definitions for a used public type"
  )
  func findsAUsedPublicType() async throws {
    let index = try await IndexUnderTest.index()
    #expect(!index.references(to: "IndexUnit").isEmpty)
    #expect(!index.definitions(of: "IndexUnit").isEmpty)
  }

  @Test("An import rule identifies the modules that supply a symbol")
  func findsSupplyingModules() async throws {
    let index = try await IndexUnderTest.index()
    #expect(index.modules(defining: "Matcher").contains("BylawsCore"))

    let suppliers = index.modules(defining: "SourceFile")
    #expect(suppliers.contains("BylawsSemantics"))
    #expect(suppliers.contains("Bylaws"))
  }

  @Test(
    "Every conformer of a semantics protocol belongs to the semantics module",
    arguments: ["InheritanceProviding", "Documented"]
  )
  func conformersStayInTheirLayer(protocolName: String) async throws {
    let index = try await IndexUnderTest.index()
    let conformers = index.conformers(of: protocolName)
    let strays = conformers.filter { $0.module != "BylawsSemantics" }

    #expect(!conformers.isEmpty)
    #expect(strays.isEmpty)
  }

  @Test(
    "The parser types are referenced only in the core and semantics modules"
  )
  func parserTypesStayContained() async throws {
    let index = try await IndexUnderTest.index()
    let users = Set(index.references(to: "FileCollector").map(\.module))
    #expect(!users.isEmpty)
    #expect(users.isSubset(of: ["BylawsSemantics", "BylawsCore"]))
  }
}
