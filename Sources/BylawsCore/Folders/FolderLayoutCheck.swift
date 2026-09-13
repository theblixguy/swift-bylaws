import BylawsPaths
public import BylawsSemantics

/// The child folders found by a layout check, with root-relative paths.
public struct FolderLayoutCheck: RuleResult, Hashable {
  /// The folders whose immediate children were checked.
  public let matchedFolders: [String]

  /// Required child folders that are missing.
  public let missingFolders: [String]

  /// Child folders whose names are outside the required set.
  public let unexpectedFolders: [String]

  let pattern: String
  let rootPath: String

  /// Returns violations and warnings at the rule's declaration.
  ///
  /// A pattern that matches no folder produces a warning. Violations list
  /// missing folders first, then unexpected folders, each in sorted path order.
  public func findings(reportedAt location: DeclarationLocation) -> Rule
    .Findings
  {
    let root = LexicalFilePath(rootPath)
    let missing = missingFolders.map { path in
      Offender(
        description: "missing folder '\(path)'",
        name: path,
        location: location,
        affectedPath: root.appending(path).string
      )
    }
    let unexpected = unexpectedFolders.map { path in
      Offender(
        description: "unexpected folder '\(path)'",
        name: path,
        location: location,
        affectedPath: root.appending(path).string
      )
    }
    return Rule.Findings(
      violations: Violations(
        rule: "contain the declared child folders",
        offenders: missing + unexpected,
        checkedCount: matchedFolders.count
      ),
      warnings: matchedFolders.isEmpty ? [Rule.Warning(
        message: "Folder pattern '\(pattern)' matched no folders. Check the pattern.",
        location: location
      )] : []
    )
  }
}
