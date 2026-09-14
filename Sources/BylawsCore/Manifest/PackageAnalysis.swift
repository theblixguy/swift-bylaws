import BylawsPaths
import BylawsSemantics

struct PackageAnalysis: Sendable {
  struct PackageImport: Sendable {
    let target: String
    let declaration: Import
  }

  let manifest: PackageManifest
  let targets: [PackageManifest.Target]
  private let filesByTarget: [String: [SourceFile]]
  private let importsByTarget: [String: [Import]]
  private let packageImportsByTarget: [String: [PackageImport]]
  private let importGraph: OrderedDirectedGraph<String>

  init(parsedCodebase: ParsedCodebase, manifest: PackageManifest) {
    let root = LexicalFilePath(parsedCodebase.rootPath)
    self.manifest = manifest
    targets = manifest.targets.knownValues.filter { target in
      !target.unresolvedValues.contains { $0.field.hasSuffix(".path") }
    }

    var filesByTarget: [String: [SourceFile]] = [:]
    for target in targets {
      let directory = root.appending(target.sourceDirectory)
      let candidates = parsedCodebase.files.filter {
        directory.contains(LexicalFilePath($0.path))
      }
      filesByTarget[target.name] = Self.selectedFiles(
        among: candidates,
        relativeTo: directory,
        for: target
      )
    }
    self.filesByTarget = filesByTarget

    let targetNameByModule = Dictionary(
      targets.map { ($0.moduleName, $0.name) },
      uniquingKeysWith: { first, _ in first }
    )
    var importsByTarget: [String: [Import]] = [:]
    var packageImportsByTarget: [String: [PackageImport]] = [:]
    var edges: [DirectedEdge<String>] = []
    for target in targets {
      let imports = filesByTarget[target.name, default: []].flatMap(\.imports)
      importsByTarget[target.name] = imports
      for declaration in imports {
        guard let imported = targetNameByModule[declaration.moduleName],
              imported != target.name
        else { continue }
        packageImportsByTarget[target.name, default: []].append(
          PackageImport(target: imported, declaration: declaration)
        )
        edges.append(.init(from: target.name, to: imported))
      }
    }
    self.importsByTarget = importsByTarget
    self.packageImportsByTarget = packageImportsByTarget
    importGraph = OrderedDirectedGraph(nodes: targets.map(\.name), edges: edges)
  }

  func files(of target: PackageManifest.Target) -> [SourceFile] {
    filesByTarget[target.name] ?? []
  }

  func imports(of target: PackageManifest.Target) -> [Import] {
    importsByTarget[target.name] ?? []
  }

  func graphTargets(ignoring ignoredTargets: Set<String> = []) -> [String] {
    importGraph.nodes.filter { !ignoredTargets.contains($0) }
  }

  func emptyTargets(ignoring ignoredTargets: Set<String> = []) -> [String] {
    targets.compactMap { target in
      guard !ignoredTargets.contains(target.name), files(of: target).isEmpty
      else { return nil }
      return target.name
    }
  }

  var unresolvedDependencyGraphValues: [PackageManifest.UnresolvedValue] {
    var issues = manifest.targets.unresolvedValues
    if !manifest.targets.conditionalValues.isEmpty {
      issues.append(
        PackageManifest.UnresolvedValue(
          field: "targets",
          expression: "conditional target declarations"
        )
      )
    }
    for target in manifest.targets.possibleValues {
      issues.append(contentsOf: target.unresolvedValues.filter {
        $0.field.hasSuffix(".path")
      })
      issues.append(contentsOf: target.dependencies.unresolvedValues)
      issues.append(contentsOf: target.dependencies.possibleValues.flatMap(
        \.unresolvedValues
      ))
      issues.append(contentsOf: target.excludedPaths.unresolvedValues)
      if !target.excludedPaths.conditionalValues.isEmpty {
        issues.append(
          PackageManifest.UnresolvedValue(
            field: "targets.\(target.name).excludedPaths",
            expression: "conditional excluded paths"
          )
        )
      }
      if case let .explicit(paths) = target.sources {
        issues.append(contentsOf: paths.unresolvedValues)
        if !paths.conditionalValues.isEmpty {
          issues.append(
            PackageManifest.UnresolvedValue(
              field: "targets.\(target.name).sources",
              expression: "conditional source paths"
            )
          )
        }
      }
    }
    return issues
  }

  func imports(from target: String, ignoring ignoredTargets: Set<String>)
    -> [String]
  {
    guard !ignoredTargets.contains(target) else { return [] }
    return importGraph.successors(of: target).filter {
      !ignoredTargets.contains($0)
    }
  }

  func importers(of target: String, ignoring ignoredTargets: Set<String>)
    -> [String]
  {
    guard !ignoredTargets.contains(target) else { return [] }
    return importGraph.predecessors(of: target).filter {
      !ignoredTargets.contains($0)
    }
  }

  func instability(
    of target: String,
    ignoring ignoredTargets: Set<String>
  ) -> Double {
    guard !ignoredTargets.contains(target) else { return 0 }
    let outgoing = importGraph.successors(of: target).count {
      !ignoredTargets.contains($0)
    }
    let incoming = importGraph.predecessors(of: target).count {
      !ignoredTargets.contains($0)
    }
    let total = outgoing + incoming
    return total == 0 ? 0 : Double(outgoing) / Double(total)
  }

  func firstImport(
    from target: String,
    to importedTarget: String,
    ignoring ignoredTargets: Set<String>
  ) -> Import? {
    guard !ignoredTargets.contains(target),
          !ignoredTargets.contains(importedTarget)
    else { return nil }
    return packageImportsByTarget[target]?.first {
      $0.target == importedTarget
    }?.declaration
  }

  private static func selectedFiles(
    among files: [SourceFile],
    relativeTo directory: LexicalFilePath,
    for target: PackageManifest.Target
  ) -> [SourceFile] {
    let excluded = target.excludedPaths.knownValues
    let included: [String]? = switch target.sources {
    case .automatic: nil
    case let .explicit(paths): paths.knownValues
    }
    return files.filter { file in
      guard let relativePath = LexicalFilePath(file.path)
        .relative(to: directory)?.string
      else { return false }
      guard !excluded.contains(where: {
        path(relativePath, belongsTo: $0)
      }) else { return false }
      guard let included else { return true }
      return included.contains { path(relativePath, belongsTo: $0) }
    }
  }

  private static func path(
    _ file: String,
    belongsTo selection: String
  ) -> Bool {
    LexicalFilePath(selection).contains(LexicalFilePath(file))
  }
}

extension Codebase {
  func packageAnalysis() async throws(CodebaseError) -> PackageAnalysis {
    try await CodebaseCache.shared.packageAnalysis(for: self)
  }
}
