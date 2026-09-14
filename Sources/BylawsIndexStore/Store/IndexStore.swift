import CIndexStore
import Foundation

/// A reader for one compiler index store.
///
/// A rule reads the store that its own build wrote.
///
/// Each compiled file contributes a unit, listed by ``unitNames()`` and read
/// by ``unit(named:)``. Its records supply the symbol occurrences returned by
/// ``occurrences(inRecordNamed:)``.
///
/// Use an index store from one task at a time. Put a shared store behind an
/// actor.
@safe
public final class IndexStore {
  private let library: IndexStoreLibrary
  private let store: indexstore_t

  /// The path of the open store.
  public let path: String

  /// Creates a store by opening `path` with the index library at
  /// `libraryPath`.
  ///
  /// - Throws: ``IndexStoreError`` when the library or the store cannot be
  ///   read.
  public init(path: String, libraryPath: String) throws(IndexStoreError) {
    self.path = path
    let library = try IndexStoreLibrary(path: libraryPath)
    self.library = library

    var error: indexstore_error_t?
    let opened = unsafe withCString(path) {
      unsafe library.storeCreate($0, &error)
    }
    guard let opened = unsafe opened else {
      throw .unreadableStore(path: path, reason: unsafe library.take(error))
    }
    unsafe store = opened
  }

  /// Creates a store by opening `path` with the index library of the
  /// active toolchain.
  ///
  /// - Throws: ``IndexStoreError`` when the toolchain holds no index
  ///   library, or when the store cannot be read.
  public convenience init(path: String) throws(IndexStoreError) {
    guard let libraryPath = IndexStoreLocation.toolchainLibraryPath() else {
      throw .missingLibrary
    }
    try self.init(path: path, libraryPath: libraryPath)
  }

  deinit {
    unsafe library.storeDispose(store)
  }

  /// Returns the names of the units in the store, sorted.
  ///
  /// A unit name is the store's own identifier for a compiled file. Pass
  /// one to ``unit(named:)``.
  public func unitNames() -> [String] {
    unsafe IndexStoreCallbackContext.collecting(using: library) { context in
      _ = unsafe library.unitsApply(store, 1, context) { rawContext, name in
        guard let context = unsafe rawContext else { return false }
        unsafe IndexStoreCallbackContext.reading(context).names.append(
          name.text
        )
        return true
      }
    }.names
  }

  /// Reads the unit named `name`.
  ///
  /// The store retains units after their source files are deleted. Check
  /// ``IndexUnit/mainFile`` when you need current files.
  ///
  /// - Throws: ``IndexStoreError/unreadableUnit(name:reason:)`` when the unit
  ///   is missing or cannot be read.
  public func unit(named name: String) throws(IndexStoreError) -> IndexUnit {
    var error: indexstore_error_t?
    let reader = unsafe withCString(name) {
      unsafe library.unitReaderCreate(store, $0, &error)
    }
    guard let reader = unsafe reader else {
      throw .unreadableUnit(name: name, reason: unsafe library.take(error))
    }
    defer { unsafe library.unitReaderDispose(reader) }

    let walk = unsafe IndexStoreCallbackContext.collecting(using: library) {
      context in
      _ = unsafe library.dependenciesApply(reader, context) {
        rawContext, rawDependency in
        guard let context = unsafe rawContext,
              let dependency = unsafe rawDependency else { return true }
        let walk = unsafe IndexStoreCallbackContext.reading(context)
        guard unsafe walk.library.dependencyKind(dependency)
          == INDEXSTORE_UNIT_DEPENDENCY_RECORD
        else { return true }
        unsafe walk.records.append(
          IndexRecord(
            name: walk.library.dependencyName(dependency).text,
            file: walk.library.dependencyPath(dependency).text
          )
        )
        return true
      }
    }

    return IndexUnit(
      name: name,
      moduleName: unsafe library.unitModuleName(reader).text,
      mainFile: unsafe library.unitMainFile(reader).text,
      records: walk.records,
      outputFile: unsafe library.unitOutputFile(reader).text
    )
  }

  /// Returns the symbol occurrences the record named `name` holds.
  ///
  /// Pass a name from ``IndexUnit/records``.
  ///
  /// - Throws: ``IndexStoreError/unreadableRecord(name:reason:)`` when the
  ///   record is missing or cannot be read.
  public func occurrences(
    inRecordNamed name: String
  ) throws(IndexStoreError) -> [IndexOccurrence] {
    var error: indexstore_error_t?
    let reader = unsafe withCString(name) {
      unsafe library.recordReaderCreate(store, $0, &error)
    }
    guard let reader = unsafe reader else {
      throw .unreadableRecord(name: name, reason: unsafe library.take(error))
    }
    defer { unsafe library.recordReaderDispose(reader) }

    let walk = unsafe IndexStoreCallbackContext.collecting(using: library) {
      context in
      _ = unsafe library.occurrencesApply(reader, context) {
        rawContext, rawOccurrence in
        guard let context = unsafe rawContext,
              let occurrence = unsafe rawOccurrence else { return true }
        let walk = unsafe IndexStoreCallbackContext.reading(context)
        unsafe walk.occurrences.append(walk.read(occurrence))
        return true
      }
    }
    return walk.occurrences
  }
}

private final class IndexStoreCallbackContext {
  let library: IndexStoreLibrary
  var names: [String] = []
  var records: [IndexRecord] = []
  var occurrences: [IndexOccurrence] = []
  var relations: [IndexRelation] = []

  static func collecting(
    using library: IndexStoreLibrary,
    _ apply: (UnsafeMutableRawPointer) -> Void
  ) -> IndexStoreCallbackContext {
    let context = IndexStoreCallbackContext(library: library)
    unsafe apply(Unmanaged.passUnretained(context).toOpaque())
    return context
  }

  static func reading(
    _ context: UnsafeMutableRawPointer
  ) -> IndexStoreCallbackContext {
    unsafe Unmanaged<IndexStoreCallbackContext>
      .fromOpaque(context)
      .takeUnretainedValue()
  }

  func read(_ occurrence: indexstore_occurrence_t) -> IndexOccurrence {
    var line: UInt32 = 0
    var column: UInt32 = 0
    unsafe library.occurrenceLineColumn(occurrence, &line, &column)

    let relations = unsafe IndexStoreCallbackContext.collecting(
      using: library
    ) { context in
      _ = unsafe library.relationsApply(occurrence, context) {
        rawContext, rawRelation in
        guard let context = unsafe rawContext,
              let relation = unsafe rawRelation else { return true }
        let walk = unsafe IndexStoreCallbackContext.reading(context)
        unsafe walk.relations.append(
          IndexRelation(
            symbol: walk.symbol(unsafe walk.library.relationSymbol(relation)),
            roles: SymbolRole(
              rawValue: unsafe walk.library.relationRoles(relation)
            )
          )
        )
        return true
      }
    }

    return IndexOccurrence(
      symbol: unsafe symbol(library.occurrenceSymbol(occurrence)),
      roles: SymbolRole(rawValue: unsafe library.occurrenceRoles(occurrence)),
      line: Int(line),
      column: Int(column),
      relations: relations.relations
    )
  }

  private init(library: IndexStoreLibrary) {
    self.library = library
  }

  // The index library uses a null symbol for an unresolved occurrence.
  private func symbol(_ symbol: indexstore_symbol_t?) -> IndexSymbol {
    guard let symbol = unsafe symbol else {
      return IndexSymbol(usr: "", name: "", kind: .other)
    }
    return IndexSymbol(
      usr: unsafe library.symbolUSR(symbol).text,
      name: unsafe library.symbolName(symbol).text,
      kind: IndexSymbol.Kind(unsafe library.symbolKind(symbol))
    )
  }
}

// Swift 6.2 and 6.3 require the outer `unsafe`. Swift 6.4 rejects it.
private func withCString<Result>(
  _ string: String,
  _ body: (UnsafePointer<CChar>) -> Result
) -> Result {
  #if compiler(>=6.4)
    string.withCString(body)
  #else
    unsafe string.withCString(body)
  #endif
}
