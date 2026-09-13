package import BylawsCore
import BylawsPaths
import BylawsSemantics

package struct DependencyPlan {
  struct File: Hashable {
    let path: String
    let group: String?
    let isSource: Bool
    let isAllowed: Bool
  }

  let files: [String: File]
  let groups: [String]
  let folderPattern: String?

  package init(
    between groups: [DependencyGroup],
    parsedCodebase: ParsedCodebase
  ) throws(DependencyGroupError) {
    var names: Set<String> = []
    let patterns = try groups.map { group throws(DependencyGroupError) in
      guard !group.name.allSatisfy(\.isWhitespace) else {
        throw .emptyName
      }
      guard names.insert(group.name).inserted
      else { throw .duplicateName(group.name) }
      for pattern in group.files {
        try DependencyGroup.validate(pattern: pattern)
      }
      return (name: group.name, globs: group.files.map { Glob($0) })
    }
    let root = LexicalFilePath(parsedCodebase.rootPath)
    var files: [String: File] = [:]
    for file in parsedCodebase.files {
      let path = LexicalFilePath(file.path)
      guard let relative = path.relative(to: root) else { continue }
      let matchPath = Glob.Path(relative.string)
      let matches = patterns.compactMap { group in
        group.globs.contains { $0.matches(matchPath) } ? group.name : nil
      }
      guard matches.count <= 1 else {
        throw .overlappingGroups(
          file: relative.string,
          groups: matches.sorted()
        )
      }
      files[path.string] = File(
        path: path.string, group: matches.first,
        isSource: matches.first != nil, isAllowed: false
      )
    }
    self.files = files
    self.groups = names.sorted()
    folderPattern = nil
  }

  package init(
    from sourcePatterns: [String],
    allowingReferencesTo destinationPatterns: [String],
    foldersMatching folderPattern: String?,
    parsedCodebase: ParsedCodebase
  ) throws(DependencyCheckError) {
    for pattern in sourcePatterns + destinationPatterns + [folderPattern]
      .compactMap(\.self)
    {
      try Self.validate(pattern)
    }
    self.folderPattern = folderPattern
    let sourceGlobs = sourcePatterns.map { Glob($0) }
    let destinationGlobs = destinationPatterns.map { Glob($0) }
    let folderGlob = folderPattern.map { Glob($0) }
    let root = LexicalFilePath(parsedCodebase.rootPath)
    var files: [String: File] = [:]
    var groups: Set<String> = []
    for file in parsedCodebase.files {
      let path = LexicalFilePath(file.path)
      guard let relative = path.relative(to: root) else { continue }
      var matchingFolders: [String] = []
      if let folderGlob {
        var parent = relative.removingLastComponent()
        while !parent.string.isEmpty {
          if folderGlob.matches(parent.string) {
            matchingFolders.append(parent.string)
          }
          parent = parent.removingLastComponent()
        }
      }
      guard matchingFolders.count <= 1 else {
        throw .overlappingFolders(
          file: relative.string,
          folders: matchingFolders.sorted()
        )
      }
      let group = matchingFolders.first
      if let group { groups.insert(group) }
      files[path.string] = File(
        path: path.string,
        group: group,
        isSource: sourceGlobs.contains { $0.matches(relative.string) },
        isAllowed: destinationGlobs.contains { $0.matches(relative.string) }
      )
    }
    self.files = files
    self.groups = groups.sorted()
  }

  private static func validate(_ pattern: String) throws(DependencyCheckError) {
    do {
      try DependencyGroup.validate(pattern: pattern)
    } catch {
      throw .unsupportedPattern(pattern)
    }
  }
}
