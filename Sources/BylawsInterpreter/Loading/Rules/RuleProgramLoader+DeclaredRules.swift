import BylawsCore
import BylawsSemantics

extension RuleProgramLoader {
  static func compileDeclaredRules(
    in parsedFiles: [LoadedRulesFile],
    rootRulesByID: [Rule.ID: ParsedRule],
    overrides: OverrideCompilation
  ) -> RuleCompilation {
    var compilation = RuleCompilation()
    for declared in declaredRules(in: parsedFiles) {
      if declared.file.isRoot {
        compileRootRule(
          declared,
          overriddenSubtrees: overrides.subtrees,
          compilation: &compilation
        )
      } else if declared.rule.isOverride {
        registerOverrideRule(
          declared,
          root: rootRulesByID[declared.id],
          overrides: overrides,
          compilation: &compilation
        )
      } else {
        compileLocalRule(
          declared,
          root: rootRulesByID[declared.id],
          compilation: &compilation
        )
      }
    }
    return compilation
  }

  static func compileRootRule(
    _ declared: DeclaredRule,
    overriddenSubtrees: [Rule.ID: Set<String>],
    compilation: inout RuleCompilation
  ) {
    guard !declared.rule.isOverride else {
      compilation.diagnostics.append(
        .error(
          "the root Bylaws.swift cannot contain Override declarations",
          at: declared.rule.location,
          hint: "move this Override to a module's Bylaws.swift file"
        )
      )
      return
    }
    guard compilation.declaredIDs.insert(declared.id).inserted else {
      compilation.diagnostics.append(
        duplicateRule(declared.id, at: declared.rule.location)
      )
      return
    }
    let excludedSubtrees = excludedSubtrees(
      for: declared.file,
      rule: declared.id,
      in: overriddenSubtrees
    )
    append(
      RuleCompiler.compile(
        declared.rule,
        as: declared.rule.header(),
        in: declared.parsed
      ),
      for: declared,
      scopeExclusions: excludedSubtrees,
      codebaseExclusions: excludedSubtrees,
      to: &compilation
    )
  }

  static func registerOverrideRule(
    _ declared: DeclaredRule,
    root: ParsedRule?,
    overrides: OverrideCompilation,
    compilation: inout RuleCompilation
  ) {
    let directory = declared.file.relativeDirectory
    let key = OverrideCompilation.Key(directory: directory, id: declared.id)
    guard root != nil, let entry = overrides.entries[key] else {
      compilation.diagnostics.append(
        .error(
          "'\(declared.id)' is not a rule the root file declares",
          at: declared.rule.location,
          hint: "use Rule to add a local rule. Override only replaces a rule from the root Bylaws.swift"
        )
      )
      return
    }
    guard entry.location == declared.rule.location else {
      compilation.diagnostics.append(
        duplicateRule(declared.id, at: declared.rule.location)
      )
      return
    }
    let scopeExclusions = nearestOverrides(
      below: directory,
      for: declared.id,
      in: overrides.subtrees
    )
    let codebaseExclusions = scopeExclusions.map {
      String($0.dropFirst(directory.count + 1))
    }
    append(
      entry.result,
      for: declared,
      scopeExclusions: scopeExclusions,
      codebaseExclusions: codebaseExclusions,
      to: &compilation
    )
  }

  static func compileLocalRule(
    _ declared: DeclaredRule,
    root: ParsedRule?,
    compilation: inout RuleCompilation
  ) {
    guard root == nil else {
      compilation.diagnostics.append(
        .error(
          "duplicate root rule ID '\(declared.id)'",
          at: declared.rule.location,
          hint: "use Override to replace it for this module, or pick a new ID"
        )
      )
      return
    }
    guard compilation.declaredIDs.insert(declared.id).inserted else {
      compilation.diagnostics.append(
        duplicateRule(declared.id, at: declared.rule.location)
      )
      return
    }
    append(
      RuleCompiler.compile(
        declared.rule,
        as: declared.rule.header(),
        in: declared.parsed
      ),
      for: declared,
      scopeExclusions: [],
      codebaseExclusions: [],
      to: &compilation
    )
  }

  static func append(
    _ compiled: Result<RuleCompiler.Compiled, Diagnostic>,
    for declared: DeclaredRule,
    scopeExclusions: [String],
    codebaseExclusions: [String],
    to compilation: inout RuleCompilation
  ) {
    switch compiled {
    case let .success(compiled):
      compilation.loadedRules.append(
        .init(
          rule: compiled.rule(excludingSubtrees: codebaseExclusions),
          scope: RuleScope(
            id: declared.id,
            directory: declared.file.relativeDirectory,
            excludedSubtrees: scopeExclusions,
            overrideReason: declared.rule.overrideReason
          )
        )
      )
    case let .failure(diagnostic):
      compilation.diagnostics.append(diagnostic)
    }
  }
}
