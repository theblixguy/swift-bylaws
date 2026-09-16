package import BylawsPaths

package enum RuleDependency: Sendable, Hashable, Codable {
  case file(String)
  case descendants(String)
  case rootMarkers(String)
  case sourceFiles(SourceScope)

  package struct SourceScope: Sendable, Hashable, Codable {
    let rootPath: String
    let including: [String]
    let excluding: [String]
    let discoversSwiftPackages: Bool
    let discoversXcodeProjects: Bool

    func contains(_ path: LexicalFilePath) -> Bool {
      let root = LexicalFilePath(rootPath)
      guard let relativePath = path.relative(to: root)?.string else {
        return false
      }
      if isLanguageModeInput(relativePath) { return true }
      guard relativePath.hasSuffix(".swift") else { return false }
      let globPath = Glob.Path(relativePath)
      let isIncluded = including.isEmpty
        || including.contains { Glob($0).matches(globPath) }
      return isIncluded
        && !excluding.contains { Glob($0).matches(globPath) }
    }

    private func isLanguageModeInput(_ relativePath: String) -> Bool {
      if discoversSwiftPackages,
         LexicalFilePath(relativePath).lastComponent == "Package.swift"
      {
        return true
      }
      return discoversXcodeProjects
        && relativePath.split(separator: "/").count == 2
        && relativePath.hasSuffix(".xcodeproj/project.pbxproj")
    }
  }

  package func contains(path: String) -> Bool {
    let path = LexicalFilePath(path, relativeTo: .currentDirectory)
    return contains(path: path)
  }

  package func contains(path: LexicalFilePath) -> Bool {
    switch self {
    case let .file(input): path == LexicalFilePath(input)
    case let .descendants(root): LexicalFilePath(root).contains(path)
    case let .rootMarkers(root):
      Self.isRootMarker(path, under: LexicalFilePath(root))
    case let .sourceFiles(scope): scope.contains(path)
    }
  }

  private static func isRootMarker(
    _ path: LexicalFilePath,
    under root: LexicalFilePath
  ) -> Bool {
    guard root.contains(path) else { return false }
    switch path.lastComponent {
    case "Package.swift", "MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE",
         ".git":
      return true
    default:
      return path.string.hasSuffix(".xcodeproj")
        || path.string.hasSuffix(".xcodeproj/project.pbxproj")
    }
  }
}
