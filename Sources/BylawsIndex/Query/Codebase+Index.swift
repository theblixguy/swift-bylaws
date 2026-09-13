public import BylawsCore
public import BylawsIndexStore
import BylawsSemantics

extension Codebase {
  /// Returns the compiler's index for this codebase.
  ///
  /// Rules read the index emitted by their own build. Debug builds emit it by
  /// default. Release builds require `--enable-index-store`.
  ///
  /// The first call for each resolved root, module set and unit-output set
  /// reads the store. Later calls reuse the successful result. Long-running
  /// integrations discard it after the indexed project changes.
  ///
  /// - Parameter modules: The modules to read, or `nil` for all of them.
  ///   Selecting modules skips standard-library and dependency-framework
  ///   units, which make up most stores.
  /// - Parameter unitOutputFiles: The opaque output identities of the units
  ///   in the current build, or `nil` when the store belongs to one build
  ///   configuration.
  /// - Throws: ``ProjectIndexError/indexUnavailable(_:)`` for an unavailable
  ///   or unreadable store, a missing requested module or output identity, or
  ///   unselected build configurations, and
  ///   ``ProjectIndexError/unreadableCodebase(_:)`` when the root cannot be
  ///   resolved.
  public func projectIndex(
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> ProjectIndex {
    try await ProjectIndexCache.shared.index(
      for: self,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    )
  }

  /// Returns the types that conform to `typeName` or inherit from it,
  /// directly or through another type, as the compiler resolved them.
  ///
  /// The query uses the compiler's cross-module view. Use
  /// ``/BylawsCore/Matcher/conforms(to:)-(String...)`` to inspect the
  /// conformance as written in source.
  ///
  /// Index selection, caching and errors match
  /// ``projectIndex(modules:unitOutputFiles:)``. The call records a warning
  /// and returns an empty array when the index holds no such name.
  ///
  /// - Parameters:
  ///   - typeName: The protocol or class to ask about.
  ///   - modules: The modules to read.
  ///   - unitOutputFiles: The build units to read.
  public func conformers(
    of typeName: String,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> [IndexReference] {
    try await indexReferences(
      named: typeName,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    ) { $0.conformers(of: $1) }
  }

  /// Returns the types whose own declaration or extension names `typeName`.
  ///
  /// A type that reaches `typeName` through a protocol that refines it does
  /// not appear here. Use ``conformers(of:modules:unitOutputFiles:)`` for the
  /// whole chain.
  ///
  /// Index selection, caching and errors match
  /// ``projectIndex(modules:unitOutputFiles:)``. The call records a warning
  /// and returns an empty array when the index holds no such name.
  ///
  /// - Parameters:
  ///   - typeName: The protocol or class to ask about.
  ///   - modules: The modules to read.
  ///   - unitOutputFiles: The build units to read.
  public func directConformers(
    of typeName: String,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> [IndexReference] {
    try await indexReferences(
      named: typeName,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    ) { $0.directConformers(of: $1) }
  }

  /// Returns every place that uses `symbolName`.
  ///
  /// Declaration and definition sites are omitted. Compiler identities keep
  /// same-named types from different modules separate.
  ///
  /// Index selection, caching and errors match
  /// ``projectIndex(modules:unitOutputFiles:)``. The call records a warning
  /// and returns an empty array when the index holds no such name.
  ///
  /// - Parameters:
  ///   - symbolName: The symbol to ask about.
  ///   - modules: The modules to read.
  ///   - unitOutputFiles: The build units to read.
  public func references(
    to symbolName: String,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> [IndexReference] {
    try await indexReferences(
      named: symbolName,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    ) { $0.references(to: $1) }
  }

  /// Returns every place that declares or defines `symbolName`.
  ///
  /// Index selection, caching and errors match
  /// ``projectIndex(modules:unitOutputFiles:)``. The call records a warning
  /// and returns an empty array when the index holds no such name.
  ///
  /// - Parameters:
  ///   - symbolName: The symbol to ask about.
  ///   - modules: The modules to read.
  ///   - unitOutputFiles: The build units to read.
  public func definitions(
    of symbolName: String,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> [IndexReference] {
    try await indexReferences(
      named: symbolName,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    ) { $0.definitions(of: $1) }
  }

  /// Returns every declaration, definition and reference for `symbolName`.
  ///
  /// Index selection, caching and errors match
  /// ``projectIndex(modules:unitOutputFiles:)``. The call records a warning
  /// and returns an empty array when the index holds no such name.
  ///
  /// - Parameters:
  ///   - symbolName: The symbol to ask about.
  ///   - modules: The modules to read.
  ///   - unitOutputFiles: The build units to read.
  public func occurrences(
    of symbolName: String,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil
  ) async throws(ProjectIndexError) -> [IndexReference] {
    try await indexReferences(
      named: symbolName,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    ) { $0.occurrences(of: $1) }
  }

  // An unknown name gives an empty result, which reads as a passing rule.
  private func indexReferences(
    named symbolName: String,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?,
    matching query: (ProjectIndex, String) -> [IndexReference]
  ) async throws(ProjectIndexError) -> [IndexReference] {
    let index = try await projectIndex(
      modules: modules,
      unitOutputFiles: unitOutputFiles
    )
    guard index.containsSymbol(named: symbolName) else {
      QueryWarnings.record(
        Rule.Warning(
          message: "'\(symbolName)' names no indexed symbol",
          location: DeclarationLocation.start(of: try indexRootPath())
        )
      )
      return []
    }
    return query(index, symbolName)
  }
}

extension Codebase {
  func indexRootPath() throws(ProjectIndexError) -> String {
    do {
      return try resolvedRootPath()
    } catch {
      throw .unreadableCodebase(error)
    }
  }
}
