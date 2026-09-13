import BylawsCore
import BylawsSemantics
import Foundation

enum RuleProgramLoader {
  struct LoadedRulesFile {
    let file: RulesDiscovery.DiscoveredFile
    var parsed: ParsedRulesFile
  }

  struct RuleCompilation {
    var loadedRules: [RuleProgram.LoadedRule] = []
    var diagnostics: [Diagnostic] = []
    var declaredIDs: Set<Rule.ID> = []
    var pathsThatDidNotParse: [String]? = []
  }

  struct DeclaredRule {
    let rule: ParsedRule
    let file: RulesDiscovery.DiscoveredFile
    let parsed: ParsedRulesFile

    var id: Rule.ID { Rule.ID(rule.id ?? rule.name) }
  }

  struct OverrideCompilation {
    struct Key: Hashable {
      let directory: String
      let id: Rule.ID
    }

    struct Entry {
      let location: DeclarationLocation
      let result: Result<RuleCompiler.Compiled, Diagnostic>
    }

    var subtrees: [Rule.ID: Set<String>] = [:]
    var entries: [Key: Entry] = [:]
  }

  static func load(
    _ files: [RulesDiscovery.DiscoveredFile],
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay,
    indexProvider: (any RuntimeIndexProvider)?,
    packageModuleIndex: PackageModuleIndex?
  ) async -> RuleProgram {
    var parsed = parseFiles(
      files,
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
    let rootRulesByID = rootRulesByID(in: parsed.files)
    let overrides = compileOverrides(
      in: parsed.files,
      rootRulesByID: rootRulesByID
    )
    let declared = compileDeclaredRules(
      in: parsed.files,
      rootRulesByID: rootRulesByID,
      overrides: overrides
    )
    let runtime = await compileRuntimeRules(
      in: parsed.files,
      sourceModules: resolved.sourceModules,
      indexProvider: indexProvider,
      overriddenSubtrees: overrides.subtrees,
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
      pathsThatDidNotParse: pathsThatDidNotParse
    )
  }

  static func parseFiles(
    _ files: [RulesDiscovery.DiscoveredFile],
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay = .empty
  ) -> (files: [LoadedRulesFile], diagnostics: [Diagnostic]) {
    var parsedFiles: [LoadedRulesFile] = []
    var diagnostics: [Diagnostic] = []
    for file in files {
      let source: String
      if let overlaid = overlay.text(forFileAt: file.path) {
        source = overlaid
      } else {
        do {
          source = try String(contentsOfFile: file.path, encoding: .utf8)
        } catch {
          diagnostics.append(
            .error(
              "cannot read the file: "
                + error.reportableDescription,
              at: DeclarationLocation.start(of: file.path)
            )
          )
          continue
        }
      }
      var parsed = RulesFileParser.parse(source: source, path: file.path)
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

  static func rootRulesByID(
    in parsedFiles: [LoadedRulesFile]
  ) -> [Rule.ID: ParsedRule] {
    let rootRules: [ParsedRule] =
      parsedFiles
        .first { $0.file.isRoot }?.parsed.rules ?? []
    return Dictionary(
      rootRules.map { (Rule.ID($0.id ?? $0.name), $0) },
      uniquingKeysWith: { first, _ in first }
    )
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

  static func compileOverrides(
    in parsedFiles: [LoadedRulesFile],
    rootRulesByID: [Rule.ID: ParsedRule]
  ) -> OverrideCompilation {
    var overrides = OverrideCompilation()
    for declared in declaredRules(in: parsedFiles)
      where !declared.file.isRoot && declared.rule.isOverride
    {
      let id = declared.id
      let directory = declared.file.relativeDirectory
      let key = OverrideCompilation.Key(directory: directory, id: id)
      guard let root = rootRulesByID[id], overrides.entries[key] == nil
      else { continue }
      let result = RuleCompiler.compile(
        declared.rule,
        as: declared.rule.header(inheriting: root),
        in: declared.parsed
      )
      overrides.entries[key] = .init(
        location: declared.rule.location,
        result: result
      )
      if case .success = result {
        overrides.subtrees[id, default: []].insert(directory)
      }
    }
    return overrides
  }
}
