public import BylawsSemantics

extension Codebase {
  /// The `Package.swift` manifest at the codebase root.
  ///
  /// - Throws: ``CodebaseError`` when project root resolution or source
  ///   parsing fails.
  public var packageManifest: PackageManifest {
    get async throws(CodebaseError) {
      try await packageAnalysis().manifest
    }
  }

  /// Checks `Package.swift` at the codebase root against the imports
  /// its targets write and returns the result.
  ///
  /// The check covers targets and modules declared by this manifest. Bylaws
  /// skips external-package dependencies and modules absent from the manifest.
  ///
  /// A target whose source directory holds no file in the codebase appears in
  /// ``PackageDependencyCheck/emptyTargets``. This keeps an unused dependency
  /// apart from a target whose files are excluded.
  ///
  /// - Parameter ignoredTargets: The targets to leave out of the check. A
  ///   Swift-only codebase reads a C target as empty. List every target that
  ///   holds no Swift.
  /// - Throws: ``CodebaseError`` when project root resolution or source
  ///   parsing fails.
  public func checkPackageDependencies(
    ignoring ignoredTargets: [String] = []
  ) async throws(CodebaseError) -> PackageDependencyCheck {
    let analysis = try await packageAnalysis()
    let ignoredTargets = Set(ignoredTargets)
    let targets = analysis.targets
    let declared = Set(targets.map(\.name))
    let declaredModules = Set(targets.map(\.moduleName))
    let moduleByTargetName = Dictionary(
      targets.map { ($0.name, $0.moduleName) },
      uniquingKeysWith: { first, _ in first }
    )

    var undeclared: [PackageDependencyCheck.UndeclaredDependency] = []
    var unused: [PackageDependencyCheck.UnusedDependency] = []
    var checkedImportCount = 0

    for target in targets
      where !ignoredTargets.contains(target.name)
    {
      guard target.dependencies.isComplete else { continue }
      let files = analysis.files(of: target)
      guard !files.isEmpty else {
        continue
      }

      let localDependencyNames = target.dependencies.knownValues.compactMap {
        dependency -> String? in
        switch dependency.kind {
        case .target: dependency.name
        case .byName where declared.contains(dependency.name): dependency.name
        case .byName, .product: nil
        }
      }
      let dependencyModules = Set(localDependencyNames.compactMap {
        moduleByTargetName[$0]
      })
      var imported: Set<String> = []
      for anImport in analysis.imports(of: target) {
        let module = anImport.moduleName
        imported.insert(module)
        checkedImportCount += 1
        guard declaredModules.contains(module), module != target.moduleName,
              !dependencyModules.contains(module)
        else { continue }
        undeclared.append(
          PackageDependencyCheck.UndeclaredDependency(
            target: target.name,
            module: module,
            importDeclaration: anImport
          )
        )
      }

      // A plugin runs its executable dependency instead of importing it.
      guard !target.isPlugin else { continue }

      // Only local targets qualify. An external target's module name may differ.
      for dependency in localDependencyNames {
        guard let module = moduleByTargetName[dependency],
              !imported.contains(module)
        else { continue }
        unused.append(
          PackageDependencyCheck.UnusedDependency(
            target: target.name,
            module: dependency
          )
        )
      }
    }

    return PackageDependencyCheck(
      undeclared: undeclared,
      unused: unused,
      emptyTargets: analysis.emptyTargets(ignoring: ignoredTargets),
      checkedImportCount: checkedImportCount,
      unresolvedManifestValues: analysis.unresolvedDependencyGraphValues
    )
  }
}
