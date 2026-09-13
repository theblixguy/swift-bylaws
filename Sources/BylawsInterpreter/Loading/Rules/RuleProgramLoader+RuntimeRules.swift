import BylawsCore
import BylawsSemantics

extension RuleProgramLoader {
  static func compileRuntimeRules(
    in parsedFiles: [LoadedRulesFile],
    sourceModules: SourceModuleLoadResult,
    indexProvider: (any RuntimeIndexProvider)?,
    overriddenSubtrees: [Rule.ID: Set<String>],
    declaredIDs: Set<Rule.ID>
  ) async -> RuleCompilation {
    var compilation = RuleCompilation(declaredIDs: declaredIDs)
    for loaded in parsedFiles {
      let file = loaded.file
      let parsed = loaded.parsed
      let runtimeContext = RuntimeProgramContext(
        file: parsed,
        sourceModules: sourceModules.modules(importedBy: parsed),
        importedModuleNames: parsed.imports.filter(
          \.isInterpretedSourceModule
        ).map(\.moduleName),
        indexProvider: indexProvider
      )
      do {
        let values = try await runtimeContext.resolvedRules()
        for value in values {
          let id = Rule.ID(value.id)
          registerRuntimeRule(
            id,
            at: value.location,
            for: file,
            overriddenSubtrees: overriddenSubtrees,
            compilation: &compilation
          ) { excludedSubtrees in
            RuntimeProgramCompiler.compile(
              value,
              in: parsed,
              indexProvider: indexProvider,
              excludingSubtrees: excludedSubtrees
            )
          }
        }
      } catch {
        if let paths = error.pathsThatDidNotParse {
          compilation.pathsThatDidNotParse?.append(contentsOf: paths)
        } else {
          compilation.pathsThatDidNotParse = nil
        }
        compilation.diagnostics.append(
          .error(error.message, at: error.location)
        )
      }
    }
    return compilation
  }

  static func registerRuntimeRule(
    _ id: Rule.ID,
    at location: DeclarationLocation,
    for file: RulesDiscovery.DiscoveredFile,
    overriddenSubtrees: [Rule.ID: Set<String>],
    compilation: inout RuleCompilation,
    compile: (_ excludedSubtrees: [String]) -> Rule
  ) {
    guard compilation.declaredIDs.insert(id).inserted else {
      compilation.pathsThatDidNotParse = nil
      compilation.diagnostics.append(duplicateRule(id, at: location))
      return
    }
    let exclusions = excludedSubtrees(
      for: file,
      rule: id,
      in: overriddenSubtrees
    )
    compilation.loadedRules.append(
      .init(
        rule: compile(exclusions),
        scope: RuleScope(
          id: id,
          directory: file.relativeDirectory,
          excludedSubtrees: exclusions
        )
      )
    )
  }
}
