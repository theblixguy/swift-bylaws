import BylawsCore
import BylawsPaths
import BylawsSemantics
import Foundation

struct RuntimeSourceModule: Sendable {
  let name: String
  let file: ParsedRulesFile
  let importedModuleNames: [String]
  let exportedNames: Set<String>
}

struct SourceModuleLoadResult: Sendable {
  let modules: [RuntimeSourceModule]
  let exportedSymbols: [String: [String: SupportedAPI.RuntimeType]]
  let diagnostics: [Diagnostic]

  func symbols(importedBy file: ParsedRulesFile) -> ImportedRuntimeSymbols {
    var values: [String: SupportedAPI.RuntimeType] = [:]
    var diagnostics: [Diagnostic] = []
    for imported in file.imports where imported.isInterpretedSourceModule {
      guard let exports = exportedSymbols[imported.moduleName] else { continue }
      for (name, type) in exports {
        guard values[name] == nil else {
          diagnostics.append(
            .error(
              "'\(name)' is exported by more than one imported module",
              at: imported.location,
              hint: "rename one declaration to avoid a module-qualified name"
            )
          )
          continue
        }
        values[name] = type
      }
    }
    return ImportedRuntimeSymbols(values: values, diagnostics: diagnostics)
  }

  func modules(importedBy file: ParsedRulesFile) -> [RuntimeSourceModule] {
    let graph = OrderedDirectedGraph(
      nodes: modules.map(\.name),
      edges: modules.flatMap { module in
        module.importedModuleNames.map {
          DirectedEdge(from: module.name, to: $0)
        }
      }
    )
    let roots = file.imports.lazy.filter(\.isInterpretedSourceModule)
      .map(\.moduleName)
    let reachable = Set(roots).union(graph.reachable(from: roots))
    return modules.filter { reachable.contains($0.name) }
  }
}

struct ImportedRuntimeSymbols: Sendable {
  let values: [String: SupportedAPI.RuntimeType]
  let diagnostics: [Diagnostic]
}

struct SourceModuleLoader {
  private enum State: Equatable {
    case visiting
    case loaded
    case failed
  }

  private let modulesByName: [String: PackageModuleIndex.Module]
  private let parseCachePolicy: ParseCachePolicy
  private let overlay: SourceOverlay
  private var states: [String: State] = [:]
  private var loadedModules: [RuntimeSourceModule] = []
  private var exportedSymbols: [
    String: [String: SupportedAPI.RuntimeType]
  ] = [:]
  private var diagnostics: [Diagnostic] = []

  init(
    index: PackageModuleIndex?,
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay
  ) {
    modulesByName = Dictionary(
      uniqueKeysWithValues: (index?.modules ?? []).map { ($0.name, $0) }
    )
    self.parseCachePolicy = parseCachePolicy
    self.overlay = overlay
  }

  mutating func load(imports: [ParsedImport]) -> SourceModuleLoadResult {
    for imported in imports where imported.isInterpretedSourceModule {
      load(moduleNamed: imported.moduleName, importedAt: imported.location)
    }
    return SourceModuleLoadResult(
      modules: loadedModules,
      exportedSymbols: exportedSymbols,
      diagnostics: diagnostics
    )
  }

  private mutating func load(
    moduleNamed name: String,
    importedAt location: DeclarationLocation
  ) {
    switch states[name] {
    case .loaded: return
    case .failed: return
    case .visiting:
      diagnostics.append(
        .error(
          "the imported module graph contains a cycle at '\(name)'",
          at: location
        )
      )
      states[name] = .failed
      return
    case nil: break
    }
    guard let module = modulesByName[name] else {
      diagnostics.append(
        .error(
          "the imported module '\(name)' is not available",
          at: location,
          hint: "run 'swift package --allow-writing-to-package-directory bylaws' from the package root"
        )
      )
      return
    }

    states[name] = .visiting
    var parsed = parse(module)
    let allowedDependencies = Set(module.dependencies)
    var importedModuleNames: [String] = []
    var hasFailedDependency = false
    for imported in parsed.imports {
      guard !imported.requiresTargetDependency
        || allowedDependencies.contains(imported.moduleName)
      else {
        parsed.diagnostics.append(
          .error(
            "'\(name)' has no target dependency on '\(imported.moduleName)'",
            at: imported.location
          )
        )
        hasFailedDependency = true
        continue
      }
      guard imported.isInterpretedSourceModule else { continue }
      load(
        moduleNamed: imported.moduleName,
        importedAt: imported.location
      )
      if states[imported.moduleName] == .loaded {
        importedModuleNames.append(imported.moduleName)
      } else {
        hasFailedDependency = true
      }
    }

    let imported = symbols(importedBy: parsed)
    parsed.diagnostics.append(contentsOf: imported.diagnostics)
    let symbols = RuntimeProgramResolver.resolve(
      &parsed,
      importing: imported.values
    )
    let hasErrors = parsed.diagnostics.contains { $0.severity == .error }
    guard states[name] != .failed, !hasFailedDependency, !hasErrors else {
      diagnostics.append(contentsOf: parsed.diagnostics)
      states[name] = .failed
      return
    }
    let exportedNames = Set(symbols.exported.keys)
    exportedSymbols[name] = symbols.exported
    diagnostics.append(contentsOf: parsed.diagnostics)
    loadedModules.append(
      RuntimeSourceModule(
        name: name,
        file: parsed,
        importedModuleNames: importedModuleNames,
        exportedNames: exportedNames
      )
    )
    states[name] = .loaded
  }

  private func symbols(
    importedBy file: ParsedRulesFile
  ) -> ImportedRuntimeSymbols {
    SourceModuleLoadResult(
      modules: loadedModules,
      exportedSymbols: exportedSymbols,
      diagnostics: []
    ).symbols(importedBy: file)
  }

  private mutating func parse(
    _ module: PackageModuleIndex.Module
  ) -> ParsedRulesFile {
    let primaryPath = module.sourceFiles[0]
    var combined = ParsedRulesFile(
      path: primaryPath,
      directory: LexicalFilePath(primaryPath).removingLastComponent().string
    )
    var names: Set<String> = []
    for path in module.sourceFiles {
      let source: String
      if let overlaid = overlay.text(forFileAt: path) {
        source = overlaid
      } else {
        do {
          source = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
          combined.diagnostics.append(
            .error(
              "cannot read the module source file: "
                + error.reportableDescription,
              at: DeclarationLocation.start(of: path)
            )
          )
          continue
        }
      }
      let file = RulesFileParser.parse(source: source, path: path)
      let duplicates = names.intersection(file.bindingNames)
      for name in duplicates.sorted() {
        combined.diagnostics.append(
          .error(
            "'\(name)' is declared in more than one module source file",
            at: DeclarationLocation.start(of: path)
          )
        )
      }
      names.formUnion(file.bindingNames)
      combined.imports.append(contentsOf: file.imports)
      combined.codebases.merge(file.codebases) { current, _ in current }
      combined.layerings.merge(file.layerings) { current, _ in current }
      combined.bindingNames.formUnion(file.bindingNames)
      combined.runtimeFunctions.append(contentsOf: file.runtimeFunctions)
      combined.runtimeBindings.append(contentsOf: file.runtimeBindings)
      combined.diagnostics.append(contentsOf: file.diagnostics)
      for rule in file.rules {
        combined.diagnostics.append(
          .error(
            "a rule module must return Rule values from a function or binding",
            at: rule.location
          )
        )
      }
    }
    combined.codebases = combined.codebases.mapValues {
      $0.usingParseCache(parseCachePolicy).usingOverlay(overlay)
    }
    return combined
  }
}
