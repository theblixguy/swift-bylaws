extension Codebase {
  /// Checks package imports against the stable dependencies principle.
  ///
  /// An edge is a violation when the importing target has lower instability
  /// than its dependency. The stable dependencies principle requires the
  /// lower-instability target on the destination side. Equal values pass.
  ///
  /// Repeated imports between the same target pair form one edge. The report
  /// points to the first import. Changing the dependency fixes the whole pair.
  ///
  /// The check reads only the targets the manifest declares. The modules of
  /// an external package are unknown.
  ///
  /// A target whose source directory holds no file in the codebase
  /// appears in ``DependencyStabilityCheck/emptyTargets`` and writes no
  /// import into the graph. Missing imports raise the instability of the
  /// targets they name. Include every declared target or pass omitted targets
  /// to `ignoring:`.
  ///
  /// - Parameter ignoredTargets: The targets to leave out of the graph. An
  ///   ignored target loses both incoming and outgoing edges. Keeping only
  ///   half its edges would report coupling absent from the package.
  /// - Throws: ``CodebaseError`` when project root resolution or source
  ///   parsing fails.
  public func checkDependencyStability(
    ignoring ignoredTargets: [String] = []
  ) async throws(CodebaseError) -> DependencyStabilityCheck {
    let analysis = try await packageAnalysis()
    let ignoredTargets = Set(ignoredTargets)
    let names = analysis.graphTargets(ignoring: ignoredTargets)
    let instability = Dictionary(
      uniqueKeysWithValues: names.map { name in
        (
          name,
          analysis.instability(of: name, ignoring: ignoredTargets)
        )
      }
    )

    var unstable: [DependencyStabilityCheck.UnstableDependency] = []
    var checkedEdgeCount = 0
    for name in names {
      for imported in analysis.imports(
        from: name,
        ignoring: ignoredTargets
      ) {
        checkedEdgeCount += 1
        let from = instability[name] ?? 0
        let to = instability[imported] ?? 0
        guard from < to,
              let declaration = analysis.firstImport(
                from: name,
                to: imported,
                ignoring: ignoredTargets
              )
        else { continue }
        unstable.append(
          DependencyStabilityCheck.UnstableDependency(
            target: name,
            importedTarget: imported,
            importDeclaration: declaration,
            instability: from,
            importedInstability: to
          )
        )
      }
    }

    return DependencyStabilityCheck(
      unstable: unstable,
      emptyTargets: analysis.emptyTargets(ignoring: ignoredTargets),
      checkedEdgeCount: checkedEdgeCount,
      unresolvedManifestValues: analysis.unresolvedDependencyGraphValues
    )
  }
}
