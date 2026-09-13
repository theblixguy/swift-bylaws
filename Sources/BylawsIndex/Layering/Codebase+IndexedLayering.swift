public import BylawsCore
import BylawsIndexStore
public import BylawsSemantics

extension Codebase {
  /// Checks dependencies between file-based layers with compiler index data.
  ///
  /// Use this for layers inside one Swift module, where source files do not
  /// import one another. The check maps each compiler-resolved symbol use to
  /// the layer that defines the symbol. Implicit compiler-generated uses are
  /// excluded.
  ///
  /// Set `modules` to the module that contains the layers. A smaller module
  /// set avoids reading unrelated index units.
  ///
  /// - Parameters:
  ///   - layering: The file globs and allowed dependency edges to check.
  ///   - modules: The indexed modules to read, or `nil` for all modules.
  ///   - unitOutputFiles: The build units to read, or `nil` when the index
  ///     contains one build configuration.
  ///   - location: The position for empty-layer warnings and missing required
  ///     edges, or `nil` to use this call site.
  ///   - filePath: The call site's file path when `location` is `nil`.
  ///   - line: The call site's line when `location` is `nil`.
  /// - Returns: Violations, empty-layer warnings and unused `mustImport`
  ///   edges ready for a ``/BylawsCore/Rule`` body.
  /// - Throws: ``IndexedLayeringError/invalidLayering(_:)`` for an invalid
  ///   layering, ``IndexedLayeringError/indexUnavailable(_:)`` when the index
  ///   is unavailable, or ``IndexedLayeringError/unreadableCodebase(_:)`` when
  ///   the codebase cannot be read.
  public func indexedFindings(
    of layering: Layering,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil,
    location: DeclarationLocation? = nil,
    filePath: String = #filePath,
    line: Int = #line
  ) async throws(IndexedLayeringError) -> Rule.Findings {
    let result = try await indexedLayeringCheck(
      layering,
      modules: modules,
      unitOutputFiles: unitOutputFiles
    )
    return result.findings(
      reportedAt: location ?? .callSite(filePath: filePath, line: line)
    )
  }

  func indexedLayeringCheck(
    _ layering: Layering,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?
  ) async throws(IndexedLayeringError) -> IndexedLayeringAnalyser.Findings {
    // An async let erases the thrown type, so each child task carries a Result.
    async let parsedTask = Result(catching: { () async throws(CodebaseError) in
      try await CodebaseCache.shared.parsedCodebase(for: self)
    })
    async let indexTask =
      Result(catching: { () async throws(ProjectIndexError) in
        try await projectIndex(
          modules: modules,
          unitOutputFiles: unitOutputFiles
        )
      })
    let parsedCodebase: ParsedCodebase
    do {
      parsedCodebase = try await parsedTask.get()
    } catch {
      throw .unreadableCodebase(error)
    }
    let index: ProjectIndex
    do {
      index = try await indexTask.get()
    } catch {
      throw IndexedLayeringError(error)
    }
    let analyser: IndexedLayeringAnalyser
    do {
      analyser = try IndexedLayeringAnalyser(
        layering: layering,
        parsedCodebase: parsedCodebase
      )
    } catch {
      throw .invalidLayering(error)
    }
    return analyser.check(occurrenceGroups: index.occurrenceGroups)
  }
}
