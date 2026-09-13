public import BylawsCore
import BylawsIndexStore
public import BylawsSemantics

extension Codebase {
  /// Checks that selected files reference only permitted files.
  ///
  /// All patterns are relative to the codebase root. The check permits
  /// references within one file and excludes definitions outside the codebase
  /// selection, including those in external libraries.
  ///
  /// Build the selected modules first. The check uses explicit compiler
  /// references from that build and returns violations at their source
  /// locations. Ambiguous definitions produce warnings.
  ///
  /// - Parameters:
  ///   - sourcePatterns: Globs that select files to check for references.
  ///   - destinationPatterns: Globs selecting permitted dependency files.
  ///     An empty array permits only references within the same file or an
  ///     allowed folder group.
  ///   - folderPattern: An optional glob selecting non-overlapping folders.
  ///     References within each matching folder are also permitted.
  ///     References between different matching folders must satisfy
  ///     `destinationPatterns`.
  ///   - modules: The build modules to read, or all modules when `nil`.
  ///   - unitOutputFiles: The build units to read, or `nil` when the index
  ///     contains one build configuration.
  ///   - location: The reporting location for warnings, or this call site.
  ///   - filePath: The source file of this call.
  ///   - line: The source line of this call.
  /// - Returns: Violations and warnings for a rule to report.
  /// - Throws: ``DependencyCheckError`` for unsupported patterns, overlapping
  ///   folder groups or source and index read failures.
  public func checkDependencies(
    from sourcePatterns: [String],
    allowingReferencesTo destinationPatterns: [String],
    allowingWithinFoldersMatching folderPattern: String? = nil,
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil,
    location: DeclarationLocation? = nil,
    filePath: String = #filePath,
    line: Int = #line
  ) async throws(DependencyCheckError) -> Rule.Findings {
    let parsed = try await parsedDependencies()
    let plan = try DependencyPlan(
      from: sourcePatterns,
      allowingReferencesTo: destinationPatterns,
      foldersMatching: folderPattern,
      parsedCodebase: parsed
    )
    return try await dependencyFindings(
      plan: plan,
      checkingCycles: false,
      modules: modules,
      unitOutputFiles: unitOutputFiles,
      reportedAt: location ?? .callSite(filePath: filePath, line: line)
    )
  }

  func parsedDependencies() async throws(DependencyCheckError)
    -> ParsedCodebase
  {
    do {
      return try await CodebaseCache.shared.parsedCodebase(for: self)
    } catch {
      throw .unreadableCodebase(error)
    }
  }

  func dependencyFindings(
    plan: DependencyPlan,
    checkingCycles: Bool,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?,
    reportedAt location: DeclarationLocation
  ) async throws(DependencyCheckError) -> Rule.Findings {
    let index: ProjectIndex
    do {
      index = try await projectIndex(
        modules: modules,
        unitOutputFiles: unitOutputFiles
      )
    } catch {
      switch error {
      case let .unreadableCodebase(error): throw .unreadableCodebase(error)
      case let .indexUnavailable(error): throw .indexUnavailable(error)
      }
    }
    return DependencyAnalyser(plan: plan).check(
      occurrenceGroups: index.occurrenceGroups,
      checkingCycles: checkingCycles,
      reportedAt: location
    )
  }
}
