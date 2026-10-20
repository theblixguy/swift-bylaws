import BylawsCore
import BylawsPaths
import BylawsSemantics

struct ReportPathScope {
  private let paths: [LexicalFilePath]

  init(paths: [String], rootPath: String) {
    let root = LexicalFilePath(rootPath)
    self.paths = paths.map {
      let path = LexicalFilePath($0, relativeTo: root)
      return path.resolvingSymbolicLinks() ?? path
    }
  }

  func contains(_ location: DeclarationLocation) -> Bool {
    contains(path: location.filePath)
  }

  func contains(path: String) -> Bool {
    let path = LexicalFilePath(path)
    let candidate = path.resolvingSymbolicLinks() ?? path
    return paths.contains { $0.contains(candidate) }
  }
}

extension RuleReport {
  func scoped(to scope: ReportPathScope) -> Self {
    Self(
      id: id,
      name: name,
      enforcement: enforcement,
      hint: hint,
      location: location,
      violations: violations.filteringOffenders {
        scope.contains(path: $0.affectedPath ?? $0.location.filePath)
      },
      warnings: warnings.filter { scope.contains($0.location) }
    )
  }
}
