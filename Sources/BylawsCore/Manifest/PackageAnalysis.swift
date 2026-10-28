import BylawsPaths
import BylawsSemantics

struct PackageAnalysis: Sendable {
  struct PackageImport: Sendable {
    let target: String
    let declaration: Import
  }

  let manifest: PackageManifest
  let manifestInput: SourceCapture.Input
  let targets: [PackageManifest.Target]
  private let filesByTarget: [String: [SourceFile]]
  private let importsByTarget: [String: [Import]]
  private let packageImportsByTarget: [String: [PackageImport]]
  private let importGraph: OrderedDirectedGraph<String>

  init(
    parsedCodebase: ParsedCodebase, manifest: PackageManifest,
    manifestInput: SourceCapture.Input
  ) {
    let root = LexicalFilePath(parsedCodebase.rootPath)
    self.manifest = manifest
    self.manifestInput = manifestInput
    targets = manifest.targets.knownValues.filter { target in
      !target.unresolvedValues.contains { $0.field.hasSuffix(".path") }
    }

    // Byte comparisons preserve path identity for different Unicode spellings.
    let files = parsedCodebase.filesAsWritten.map {
      (file: $0, path: Array(LexicalFilePath($0.path).string.utf8))
    }
    var filesByTarget: [String: [SourceFile]] = [:]
    for target in targets {
      filesByTarget[target.name] = Self.selectedFiles(
        among: files,
        relativeTo: Array(root.appending(target.sourceDirectory).string.utf8),
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
    among files: [(file: SourceFile, path: [UInt8])],
    relativeTo directory: [UInt8],
    for target: PackageManifest.Target
  ) -> [SourceFile] {
    let excluded = target.excludedPaths.knownValues.map {
      Array(LexicalFilePath($0).string.utf8)
    }
    let included: [[UInt8]]? = switch target.sources {
    case .automatic: nil
    case let .explicit(paths):
      paths.knownValues.map { Array(LexicalFilePath($0).string.utf8) }
    }
    return files.compactMap { file, path in
      guard let relativePath = relativePath(path[...], under: directory),
            !excluded.contains(where: {
              Self.relativePath(relativePath, under: $0) != nil
            })
      else { return nil }
      if let included, !included.contains(where: {
        Self.relativePath(relativePath, under: $0) != nil
      }) { return nil }
      return file
    }
  }

  private static func relativePath(
    _ path: ArraySlice<UInt8>,
    under directory: [UInt8]
  ) -> ArraySlice<UInt8>? {
    guard !directory.isEmpty else { return path }
    guard path.starts(with: directory) else { return nil }
    let suffix = path.dropFirst(directory.count)
    guard !suffix.isEmpty, directory.last != UInt8(ascii: "/") else {
      return suffix
    }
    guard suffix.first == UInt8(ascii: "/") else { return nil }
    return suffix.dropFirst()
  }
}

extension Codebase {
  func packageAnalysis() async throws(CodebaseError) -> PackageAnalysis {
    try await CodebaseCache.shared.packageAnalysis(for: self)
  }
}
