import Foundation

/// An in-memory index of compiler-resolved symbols across modules.
public struct ProjectIndex: Sendable {
  private let occurrenceStorage: IndexOccurrences

  private let usrsByName: [String: Set<String>]

  private let conformersByUSR: [String: [IndexReference]]

  /// The modules the index read.
  public let modules: Set<String>

  /// The number of files the index read.
  public let fileCount: Int

  /// Creates an index of the symbols `store` records.
  ///
  /// - Parameters:
  ///   - store: The store to read.
  ///   - modules: The modules to read, or `nil` for all of them. Selecting
  ///     modules skips standard-library and dependency-framework units, which
  ///     make up most stores.
  ///   - unitOutputFiles: The opaque output identities of the units in the
  ///     current build, or `nil` when the store belongs to one build
  ///     configuration. Read these values from ``IndexUnit/outputFile`` or
  ///     from the build system. Treat them as opaque identities even when
  ///     they look like file paths.
  ///   - skippingDeletedFiles: Whether to leave out a unit whose source
  ///     file no longer exists. A store keeps the unit of a deleted file
  ///     until the next clean build.
  ///
  /// Multiple builds of one source file can contain mutually exclusive
  /// declarations. Without `unitOutputFiles`, the initialiser rejects such a
  /// store.
  ///
  /// SwiftPM command plugins compile their executable dependencies as tool
  /// units. When a store contains both a normal unit and its plugin-tool copy,
  /// the initialiser uses the normal unit. An explicit `unitOutputFiles`
  /// selection can select either one.
  /// - Throws: ``IndexStoreError`` when a unit or record cannot be read, when
  ///   the store has no unit for a requested module or output identity, or
  ///   when several build configurations have no explicit output selection.
  public init(
    store: IndexStore,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil,
    skippingDeletedFiles: Bool = true
  ) throws(IndexStoreError) {
    try self.init(
      store: store,
      modules: modules,
      unitOutputFiles: unitOutputFiles,
      skippingDeletedFiles: skippingDeletedFiles,
      includingFile: { _ in true }
    )
  }

  package init(
    store: IndexStore,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?,
    skippingDeletedFiles: Bool = true,
    includingFile: (String) -> Bool,
    mapFilePath: (String) -> String = { $0 }
  ) throws(IndexStoreError) {
    var references: [String: Set<IndexReference>] = [:]
    var names: [String: Set<String>] = [:]
    var conformers: [String: Set<IndexReference>] = [:]
    var readModules: Set<String> = []
    var files: Set<String> = []

    var internedIdentifiers: Set<String> = []
    func interned(_ usr: String) -> String {
      if let existing = internedIdentifiers.firstIndex(of: usr) {
        return internedIdentifiers[existing]
      }
      internedIdentifiers.insert(usr)
      return usr
    }

    var units: [IndexUnit] = []
    for unitName in store.unitNames() {
      units.append(try store.unit(named: unitName))
    }
    let selectedUnits: [IndexUnit]
    if let unitOutputFiles {
      let availableOutputFiles = Set(units.map(\.outputFile))
      let missingOutputFiles = unitOutputFiles.subtracting(availableOutputFiles)
      guard missingOutputFiles.isEmpty else {
        throw .missingUnitOutputFiles(outputFiles: missingOutputFiles)
      }
      selectedUnits = units.filter {
        unitOutputFiles.contains($0.outputFile)
      }
    } else {
      selectedUnits = Self.preferringNonPluginToolUnits(in: units)
    }
    let currentUnits = selectedUnits.filter { unit in
      !skippingDeletedFiles || unit.mainFile.isEmpty
        || FileManager.default.fileExists(atPath: unit.mainFile)
    }
    let availableModules = Set(currentUnits.map(\.moduleName))
    if let modules {
      let missingModules = modules.subtracting(availableModules)
      guard missingModules.isEmpty else {
        throw .missingModules(
          names: missingModules,
          available: availableModules
        )
      }
    }
    let requestedUnits = currentUnits.filter { unit in
      (modules?.contains(unit.moduleName) ?? true)
        && includingFile(unit.mainFile)
    }
    if unitOutputFiles == nil {
      try Self.requireOneBuildConfiguration(in: requestedUnits)
    }

    for unit in requestedUnits {
      readModules.insert(unit.moduleName)
      if !unit.mainFile.isEmpty { files.insert(mapFilePath(unit.mainFile)) }

      for record in unit.records {
        let sourceFile = record.file.isEmpty ? unit.mainFile : record.file
        let file = sourceFile.isEmpty ? sourceFile : mapFilePath(sourceFile)
        if !file.isEmpty { files.insert(file) }
        for occurrence in try store.occurrences(inRecordNamed: record.name) {
          guard !occurrence.symbol.usr.isEmpty else { continue }
          let usr = interned(occurrence.symbol.usr)
          let reference = IndexReference(
            symbol: IndexSymbol(
              usr: usr,
              name: occurrence.symbol.name,
              kind: occurrence.symbol.kind
            ),
            module: unit.moduleName,
            file: file,
            line: occurrence.line,
            column: occurrence.column,
            roles: occurrence.roles
          )
          references[usr, default: []].insert(reference)
          names[occurrence.symbol.name, default: []].insert(usr)

          for relation in occurrence.relations(having: .baseOf) {
            conformers[usr, default: []].insert(
              IndexReference(
                symbol: IndexSymbol(
                  usr: interned(relation.symbol.usr),
                  name: relation.symbol.name,
                  kind: relation.symbol.kind
                ),
                module: unit.moduleName,
                file: file,
                line: occurrence.line,
                column: occurrence.column,
                roles: relation.roles
              )
            )
          }
        }
      }
    }

    occurrenceStorage = IndexOccurrences(references.values.joined())
    usrsByName = names
    conformersByUSR = conformers.mapValues {
      $0.sorted(by: IndexReference.areInStableOrder)
    }
    self.modules = readModules
    fileCount = files.count
  }

  private static func preferringNonPluginToolUnits(
    in units: [IndexUnit]
  ) -> [IndexUnit] {
    let sourceBuilds = Set(
      units.lazy.filter { !$0.isSwiftPMPluginTool }
        .map { SourceUnit(module: $0.moduleName, file: $0.mainFile) }
    )
    return units.filter { unit in
      !unit.isSwiftPMPluginTool
        || !sourceBuilds.contains(
          SourceUnit(module: unit.moduleName, file: unit.mainFile)
        )
    }
  }

  /// Returns the types that conform to `typeName` or inherit from it,
  /// directly or through another type, as the compiler resolved them.
  ///
  /// Results use compiler-resolved identities across modules and typealiases,
  /// including conformances declared in extensions.
  ///
  /// The compiler records only the conformance as written. A type that
  /// reaches `typeName` through a protocol that refines it appears here
  /// but not in ``directConformers(of:)``.
  public func conformers(of typeName: String) -> [IndexReference] {
    var found: [IndexReference] = []
    var walked: Set<String> = []
    var reported: Set<IndexReference> = []
    var pending = Array(identifiers(for: typeName))

    while let usr = pending.popLast() {
      guard walked.insert(usr).inserted else { continue }
      for conformer in conformersByUSR[usr] ?? [] {
        if reported.insert(conformer).inserted { found.append(conformer) }
        pending.append(conformer.symbol.usr)
      }
    }
    return found.sorted(by: IndexReference.areInStableOrder)
  }

  /// Returns the types whose own declaration or extension names `typeName`.
  ///
  /// A type that reaches `typeName` through a protocol that refines it
  /// does not appear here. Use ``conformers(of:)`` for the whole chain.
  public func directConformers(of typeName: String) -> [IndexReference] {
    identifiers(for: typeName)
      .flatMap { conformersByUSR[$0] ?? [] }
      .sorted(by: IndexReference.areInStableOrder)
  }

  /// Returns every place that uses `symbolName`.
  ///
  /// The result leaves out the places that declare or define it.
  public func references(to symbolName: String) -> [IndexReference] {
    references(toIdentifiers: identifiers(for: symbolName))
  }

  /// Returns uses of the symbols in `definitions`.
  public func references(to definitions: [IndexReference]) -> [IndexReference] {
    references(toIdentifiers: Set(definitions.map(\.symbol.usr)))
  }

  package func references(
    toIdentifiers identifiers: Set<String>
  ) -> [IndexReference] {
    occurrenceStorage.matching(identifiers).filter {
      $0.roles.contains(.reference) && !$0.roles.contains(.definition)
    }
  }

  /// Returns the declarations and definitions in the index.
  public func definitions() -> [IndexReference] {
    occurrenceStorage.all.filter {
      $0.roles.contains(.definition) || $0.roles.contains(.declaration)
    }
  }

  /// Returns every place that declares or defines `symbolName`.
  public func definitions(of symbolName: String) -> [IndexReference] {
    occurrences(of: symbolName).filter {
      $0.roles.contains(.definition) || $0.roles.contains(.declaration)
    }
  }

  /// Returns every place `symbolName` appears, whatever it does there.
  public func occurrences(of symbolName: String) -> [IndexReference] {
    occurrenceStorage.matching(identifiers(for: symbolName))
  }

  /// Returns the compiler occurrences at an exact source position.
  ///
  /// Use the file path and source from the indexed build, with lines and
  /// UTF-8 byte columns starting at 1. The result includes every occurrence
  /// at that position and is empty when the index has none.
  ///
  /// - Complexity: O(log n + k), where n is the number of indexed occurrences
  ///   and k is the number at this position.
  public func occurrences(
    in file: String,
    line: Int,
    column: Int
  ) -> [IndexReference] {
    occurrenceStorage.at(file: file, line: line, column: column)
  }

  /// Returns the modules that supply `symbolName`.
  ///
  /// An import is unused when its module supplies none of the file's symbols.
  ///
  /// Re-exported symbols count as supplied by both modules. Either module can
  /// satisfy the import.
  public func modules(defining symbolName: String) -> Set<String> {
    Set(definitions(of: symbolName).map(\.module))
  }

  private func identifiers(for name: String) -> Set<String> {
    usrsByName[name] ?? []
  }

  package func containsSymbol(named name: String) -> Bool {
    usrsByName[name] != nil
  }

  package var occurrenceGroups: some Sequence<[IndexReference]> {
    occurrenceStorage.groups
  }

  private static func requireOneBuildConfiguration(
    in units: [IndexUnit]
  ) throws(IndexStoreError) {
    var outputsBySource: [SourceUnit: Set<String>] = [:]
    for unit in units where !unit.mainFile.isEmpty {
      outputsBySource[
        SourceUnit(module: unit.moduleName, file: unit.mainFile),
        default: []
      ].insert(unit.outputFile)
    }
    let conflict =
      outputsBySource
        .filter { $0.value.count > 1 }
        .sorted { lhs, rhs in
          if lhs.key.module != rhs.key.module {
            return lhs.key.module < rhs.key.module
          }
          return lhs.key.file < rhs.key.file
        }
        .first
    if let conflict {
      throw .mixedBuildConfigurations(
        module: conflict.key.module,
        file: conflict.key.file,
        outputFiles: conflict.value
      )
    }
  }

  private struct SourceUnit: Hashable {
    let module: String
    let file: String
  }
}

extension IndexUnit {
  fileprivate var isSwiftPMPluginTool: Bool {
    URL(fileURLWithPath: outputFile).pathComponents.contains {
      $0.hasSuffix(SwiftPMBuildPath.pluginToolSuffix)
    }
  }
}

private enum SwiftPMBuildPath {
  static let pluginToolSuffix = "-tool.build"
}
