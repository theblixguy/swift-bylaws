import BylawsIndexStore
import Testing

@Suite(
  "Index store reading",
  .enabled(
    if: IndexUnderTest.isAvailable,
    "This build wrote no index store. Build in debug first."
  ),
  .tags(.indexStore)
)
struct IndexStoreTests {
  @Test("The toolchain supplies an index library")
  func findsTheLibrary() throws {
    let path = try #require(IndexStoreLocation.toolchainLibraryPath())
    #expect(path.contains("libIndexStore"))
  }

  @Test("Opening a store returns its unit names")
  func readsUnits() throws {
    let store = try openStore()
    let names = store.unitNames()
    #expect(!names.isEmpty)
    #expect(names.contains { $0.hasPrefix("IndexStore.swift") })
  }

  @Test("A unit contains its module, file and records")
  func readsOneUnit() throws {
    let store = try openStore()
    let unit = try indexSymbolUnit(in: store)
    #expect(unit.moduleName == "BylawsIndexStore")
    #expect(unit.mainFile.hasSuffix("IndexSymbol.swift"))
    #expect(!unit.outputFile.isEmpty)
    #expect(!unit.records.isEmpty)
    #expect(unit.records.allSatisfy { !$0.file.isEmpty })
  }

  @Test("A record contains occurrences with symbols and roles")
  func readsOccurrences() throws {
    let store = try openStore()
    let unit = try indexSymbolUnit(in: store)
    let record = try #require(unit.records.first)
    let occurrences = try store.occurrences(inRecordNamed: record.name)

    #expect(!occurrences.isEmpty)
    let symbol = try #require(
      occurrences.first { $0.symbol.name == "IndexSymbol" }
    )
    #expect(symbol.symbol.kind == .struct)
    #expect(symbol.symbol.usr.hasPrefix("s:"))
    #expect(symbol.line > 0)
  }

  @Test("A missing unit reports the unit name")
  func reportsAMissingUnit() throws {
    let store = try openStore()
    do {
      _ = try store.unit(named: "NoSuchUnit")
      Issue.record("The missing unit opened.")
    } catch {
      guard case let .unreadableUnit(name, reason) = error else {
        Issue.record("The store reported the wrong error: \(error)")
        return
      }
      #expect(name == "NoSuchUnit")
      #expect(!reason.isEmpty)
    }
  }

  @Test("A missing record reports the record name")
  func reportsAMissingRecord() throws {
    let store = try openStore()
    do {
      _ = try store.occurrences(inRecordNamed: "NoSuchRecord")
      Issue.record("The missing record opened.")
    } catch {
      guard case let .unreadableRecord(name, reason) = error else {
        Issue.record("The store reported the wrong error: \(error)")
        return
      }
      #expect(name == "NoSuchRecord")
      #expect(!reason.isEmpty)
    }
  }

  private func openStore() throws -> IndexStore {
    try IndexStore(path: IndexUnderTest.storePath())
  }

  private func indexSymbolUnit(in store: IndexStore) throws -> IndexUnit {
    let units = store.unitNames()
      .filter { $0.hasPrefix("IndexSymbol.swift") }
      .compactMap { try? store.unit(named: $0) }
    return try #require(
      units.first { $0.moduleName == "BylawsIndexStore" }
    )
  }
}

@Suite("Index store errors", .tags(.indexStore))
struct IndexStoreErrorTests {
  @Test("Opening a missing library reports the loader's reason")
  func reportsAMissingLibrary() throws {
    let libraryPath = "/nowhere/libIndex.dylib"
    let error = #expect(throws: IndexStoreError.self) {
      try IndexStore(path: "/nowhere", libraryPath: libraryPath)
    }
    guard case let .unreadableLibrary(path, reason) = try #require(error) else {
      Issue.record("the loader failed with \(String(describing: error))")
      return
    }
    #expect(path == libraryPath)
    #expect(!reason.isEmpty)
    #expect(try #require(error).description.contains(reason))
  }

  @Test(
    "Opening a missing store throws an error",
    .enabled(
      if: IndexStoreLocation.toolchainLibraryPath() != nil,
      "This toolchain has no IndexStore library."
    )
  )
  func reportsAMissingStore() throws {
    let library = try #require(IndexStoreLocation.toolchainLibraryPath())
    #expect(throws: IndexStoreError.self) {
      try IndexStore(path: "/nowhere/index/store", libraryPath: library)
    }
  }
}
