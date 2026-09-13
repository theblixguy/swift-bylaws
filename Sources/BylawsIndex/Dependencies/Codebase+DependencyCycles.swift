public import BylawsCore
public import BylawsSemantics

extension Codebase {
  /// Reports the first dependency cycle between named groups of files.
  ///
  /// Build the selected modules first. The check uses explicit compiler
  /// references and reports one source location per edge, in sorted group-name
  /// order. It excludes references within one group and files outside all groups.
  /// Group names must be distinct and non-empty. Selected files cannot belong
  /// to more than one group.
  ///
  /// An empty group list, groups without index data and ambiguous definitions
  /// produce warnings.
  ///
  /// - Parameters:
  ///   - groups: Named file selections, with globs relative to the codebase root.
  ///   - modules: The build modules to read, or all modules when `nil`.
  ///   - unitOutputFiles: The build units to read, or `nil` for a single build
  ///     configuration.
  ///   - location: The warning location, or this call site when `nil`.
  ///   - filePath: The source file of this call.
  ///   - line: The source line of this call.
  /// - Throws: ``DependencyCheckError`` for group, source or index failures.
  public func checkDependencyCycles(
    between groups: [DependencyGroup],
    modules: Set<String>? = nil,
    unitOutputFiles: Set<String>? = nil,
    location: DeclarationLocation? = nil,
    filePath: String = #filePath,
    line: Int = #line
  ) async throws(DependencyCheckError) -> Rule.Findings {
    let parsed = try await parsedDependencies()
    let plan: DependencyPlan
    do {
      plan = try DependencyPlan(between: groups, parsedCodebase: parsed)
    } catch {
      throw .groups(error)
    }
    return try await dependencyFindings(
      plan: plan,
      checkingCycles: true,
      modules: modules,
      unitOutputFiles: unitOutputFiles,
      reportedAt: location ?? .callSite(filePath: filePath, line: line)
    )
  }
}
