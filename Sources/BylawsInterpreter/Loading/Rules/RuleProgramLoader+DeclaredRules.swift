import BylawsCore
import BylawsPaths
import BylawsSemantics

extension RuleProgramLoader {
  static func compileDeclaredRules(
    in parsedFiles: [LoadedRulesFile]
  ) -> RuleCompilation {
    var compilation = RuleCompilation()
    var headers: [Rule.ID: [String: RuleCompiler.Header]] = [:]
    var compiledRules: [(
      declared: DeclaredRule,
      compiled: RuleCompiler.Compiled
    )] = []

    for declared in declaredRules(in: parsedFiles) {
      let directory = declared.file.relativeDirectory
      let path = LexicalFilePath(directory)
      let previous = headers[declared.id] ?? [:]
      let parent = previous.lazy.filter { ancestor, _ in
        ancestor != directory
          && (ancestor.isEmpty || LexicalFilePath(ancestor).contains(path))
      }.max { $0.key.count < $1.key.count }?.value

      guard previous[directory] == nil else {
        compilation.diagnostics.append(duplicateRule(
          declared.id,
          at: declared.rule.location
        ))
        continue
      }
      let header: RuleCompiler.Header
      if declared.rule.isOverride {
        guard !declared.file.isRoot else {
          compilation.diagnostics.append(.error(
            "the root Bylaws.swift cannot contain Override declarations",
            at: declared.rule.location,
            hint: "move this Override to a child folder's Bylaws.swift file"
          ))
          continue
        }
        guard let parent else {
          compilation.diagnostics.append(.error(
            "Override must name a rule from a parent folder",
            at: declared.rule.location,
            hint: "use Rule to declare '\(declared.id)' in this folder"
          ))
          continue
        }
        header = declared.rule.header(inheriting: parent)
      } else {
        guard compilation.declaredIDs.insert(declared.id).inserted else {
          let diagnostic: Diagnostic = if parent != nil {
            .error(
              "Rule must use a unique ID",
              at: declared.rule.location,
              hint: "use Override to replace '\(declared.id)' in this folder, or choose another ID"
            )
          } else {
            duplicateRule(declared.id, at: declared.rule.location)
          }
          compilation.diagnostics.append(diagnostic)
          continue
        }
        header = declared.rule.header()
      }
      headers[declared.id, default: [:]][directory] = header
      switch RuleCompiler.compile(
        declared.rule,
        as: header,
        in: declared.parsed
      ) {
      case let .success(compiled):
        compiledRules.append((declared, compiled))
        if declared.rule.isOverride {
          compilation.overriddenSubtrees[declared.id, default: []]
            .insert(directory)
        }
      case let .failure(diagnostic):
        compilation.diagnostics.append(diagnostic)
      }
    }

    for (declared, compiled) in compiledRules {
      let directory = declared.file.relativeDirectory
      let exclusions = nearestOverrides(
        below: directory,
        for: declared.id,
        in: compilation.overriddenSubtrees
      )
      let relativeExclusions = exclusions.map {
        directory.isEmpty ? $0 : String($0.dropFirst(directory.count + 1))
      }
      compilation.loadedRules.append(.init(
        rule: compiled.rule(excludingSubtrees: relativeExclusions),
        scope: RuleScope(
          id: declared.id,
          directory: directory,
          excludedSubtrees: exclusions,
          overrideReason: declared.rule.overrideReason
        )
      ))
    }
    return compilation
  }
}
