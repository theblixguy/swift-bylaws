import BylawsCore
import BylawsSemantics

enum RuleProgramLoader {
  struct LoadedRulesFile {
    let file: RulesDiscovery.DiscoveredFile
    var parsed: ParsedRulesFile
  }

  struct RuleCompilation {
    var loadedRules: [RuleProgram.LoadedRule] = []
    var diagnostics: [Diagnostic] = []
    var declaredIDs: Set<Rule.ID> = []
    var overriddenSubtrees: [Rule.ID: Set<String>] = [:]
    var pathsThatDidNotParse: [String]? = []
  }

  struct DeclaredRule {
    let rule: ParsedRule
    let file: RulesDiscovery.DiscoveredFile
    let parsed: ParsedRulesFile

    var id: Rule.ID { Rule.ID(rule.id ?? rule.name) }
  }

  static func load(
    _ files: [RulesDiscovery.DiscoveredFile],
    parsedRoot: ParsedRulesFile? = nil,
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay,
    indexProvider: (any RuntimeIndexProvider)?,
    packageModuleIndex: PackageModuleIndex?
  ) async -> RuleProgram {
    var parsed = parseFiles(
      files,
      parsedRoot: parsedRoot,
      parseCachePolicy: parseCachePolicy,
      overlay: overlay
    )
    var diagnostics = parsed.diagnostics
    let resolved = resolveSourceModules(
      in: &parsed.files,
      packageModuleIndex: packageModuleIndex,
      parseCachePolicy: parseCachePolicy,
      overlay: overlay
    )
    diagnostics.append(contentsOf: resolved.diagnostics)
    let declared = compileDeclaredRules(in: parsed.files)
    let runtime = await compileRuntimeRules(
      in: parsed.files,
      sourceModules: resolved.sourceModules,
      indexProvider: indexProvider,
      overriddenSubtrees: declared.overriddenSubtrees,
      declaredIDs: declared.declaredIDs
    )
    diagnostics.append(contentsOf: declared.diagnostics)
    let pathsThatDidNotParse: [String] =
      if diagnostics.contains(where: { $0.severity == .error }) {
        []
      } else {
        runtime.pathsThatDidNotParse ?? []
      }
    diagnostics.append(contentsOf: runtime.diagnostics)
    return RuleProgram(
      loadedRules: declared.loadedRules + runtime.loadedRules,
      diagnostics: diagnostics,
      ruleFileStatus: .found,
      pathsThatDidNotParse: pathsThatDidNotParse,
      ruleSourcePaths: parsed.files.map(\.file.path)
        + resolved.sourceModules.modules.flatMap(\.sourcePaths)
    )
  }

  static func parseFiles(
    _ files: [RulesDiscovery.DiscoveredFile],
    parsedRoot: ParsedRulesFile? = nil,
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay = .empty
  ) -> (files: [LoadedRulesFile], diagnostics: [Diagnostic]) {
    var parsedFiles: [LoadedRulesFile] = []
    var diagnostics: [Diagnostic] = []
    for file in files {
      var parsed = if let parsedRoot, parsedRoot.path == file.path {
        parsedRoot
      } else {
        ParsedRulesFile.loaded(at: file.path, overlay: overlay)
      }
      if !file.isRoot, let diagnostic = parsed.discoveryOutsideRootDiagnostic {
        diagnostics.append(diagnostic)
      }
      parsed.codebases = parsed.codebases.mapValues {
        $0.usingParseCache(parseCachePolicy).usingOverlay(overlay)
      }
      parsedFiles.append(LoadedRulesFile(file: file, parsed: parsed))
    }
    return (parsedFiles, diagnostics)
  }

  static func resolveSourceModules(
    in parsedFiles: inout [LoadedRulesFile],
    packageModuleIndex: PackageModuleIndex?,
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay
  ) -> (sourceModules: SourceModuleLoadResult, diagnostics: [Diagnostic]) {
    var sourceModuleLoader = SourceModuleLoader(
      index: packageModuleIndex,
      parseCachePolicy: parseCachePolicy,
      overlay: overlay
    )
    let sourceModules = sourceModuleLoader.load(
      imports: parsedFiles.flatMap(\.parsed.imports)
    )
    var diagnostics = sourceModules.diagnostics
    for index in parsedFiles.indices {
      var parsed = parsedFiles[index].parsed
      let imported = sourceModules.symbols(importedBy: parsed)
      parsed.diagnostics.append(contentsOf: imported.diagnostics)
      RuntimeProgramResolver.resolve(&parsed, importing: imported.values)
      diagnostics.append(contentsOf: parsed.diagnostics)
      parsedFiles[index].parsed = parsed
    }
    return (sourceModules, diagnostics)
  }

  static func declaredRules(
    in parsedFiles: [LoadedRulesFile]
  ) -> [DeclaredRule] {
    parsedFiles.flatMap { loaded in
      loaded.parsed.rules.map {
        DeclaredRule(rule: $0, file: loaded.file, parsed: loaded.parsed)
      }
    }
  }
}
