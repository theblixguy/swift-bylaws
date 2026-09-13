import BylawsCore
import BylawsPaths
import BylawsSemantics

extension RuleProgramLoader {
  static func excludedSubtrees(
    for file: RulesDiscovery.DiscoveredFile,
    rule id: Rule.ID,
    in overriddenSubtrees: [Rule.ID: Set<String>]
  ) -> [String] {
    guard file.isRoot else { return [] }
    return nearestOverrides(
      below: file.relativeDirectory,
      for: id,
      in: overriddenSubtrees
    )
  }

  static func nearestOverrides(
    below directory: String,
    for id: Rule.ID,
    in overriddenSubtrees: [Rule.ID: Set<String>]
  ) -> [String] {
    let scope = LexicalFilePath(directory)
    let descendants = (overriddenSubtrees[id] ?? []).filter { candidate in
      candidate != directory
        && (directory.isEmpty || scope.contains(LexicalFilePath(candidate)))
    }
    return descendants.filter { candidate in
      let path = LexicalFilePath(candidate)
      return !descendants.contains { possibleParent in
        possibleParent != candidate
          && LexicalFilePath(possibleParent).contains(path)
      }
    }.sorted()
  }

  static func duplicateRule(
    _ id: Rule.ID,
    at location: DeclarationLocation
  ) -> Diagnostic {
    .error(
      "'\(id)' is declared twice",
      at: location,
      hint: "give each rule its own ID"
    )
  }
}
