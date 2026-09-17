import BylawsPaths

extension Codebase {
  package func recordSourceDependencies(rootPath: String?) async {
    guard let rootPath else { return }
    await recordRootDependency(under: rootPath)
    let projects: LanguageMode.Projects = switch swiftLanguageMode {
    case let .automatic(projects): projects
    case .v4, .v5, .v6: []
    }
    await RuleDependencyTracking.record(.sourceFiles(.init(
      rootPath: rootPath,
      including: including.map(\.pattern),
      excluding: excluding.map(\.pattern),
      discoversSwiftPackages: projects.contains(.swiftPM),
      discoversXcodeProjects: projects.contains(.xcode)
    )))
  }

  package func recordSwiftPackageAnalysisDependencies(
    rootPath: String?
  ) async {
    await recordSourceDependencies(rootPath: rootPath)
    guard let rootPath else { return }
    let manifest = LexicalFilePath(rootPath).appending("Package.swift").string
    await RuleDependencyTracking.record(.file(manifest))
  }

  package func recordFileDependency(
    _ path: String,
    projectRoot: String
  ) async {
    if case .sources = root.strategy { return }
    await recordRootDependency(under: projectRoot)
    await RuleDependencyTracking.record(.file(path))
  }

  package func recordDescendantsDependency(_ path: String) async {
    if case .sources = root.strategy { return }
    await recordRootDependency(under: path)
    await RuleDependencyTracking.record(.descendants(path))
  }

  private func recordRootDependency(under rootPath: String) async {
    guard case .automatic = root.strategy else { return }
    await RuleDependencyTracking.record(.rootMarkers(rootPath))
  }
}
