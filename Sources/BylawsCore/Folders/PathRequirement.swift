import BylawsPaths
public import BylawsSemantics

extension Selection where Element: Located {
  package func pathRequirement(_ patterns: [String]) -> Matcher<Element> {
    .pathRequirement(patterns, relativeTo: rootPath)
  }
}

extension Matcher where Subject: Located {
  package static func pathRequirement(
    _ patterns: [String],
    relativeTo rootPath: String
  ) -> Matcher {
    let globs = patterns.map { Glob($0) }
    let root = LexicalFilePath(rootPath)
    return Matcher("be in paths matching \(patterns.quotedList)") { element in
      guard let path = LexicalFilePath(element.location.filePath)
        .relative(to: root)
      else {
        return false
      }
      let relativePath = Glob.Path(path.string)
      return globs.contains { $0.matches(relativePath) }
    }
  }
}

extension Violations where Element: Located {
  /// Creates violations for files or declarations outside all permitted paths.
  ///
  /// Globs match the complete root-relative file path. For example,
  /// `"Sources/App/*/Views/**"` permits files below each feature's `Views`
  /// folder, including files in nested folders.
  public init(
    outsidePaths patterns: [String],
    in selection: Selection<Element>
  ) {
    self.init(of: selection.pathRequirement(patterns), in: selection)
  }
}
