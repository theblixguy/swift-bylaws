public import BylawsSemantics

/// Import edges between targets in one package.
///
/// The graph keeps one edge for each target pair. Importing `Domain` in
/// twenty files creates one edge. Only manifest targets appear. External packages do
/// not expose their module-to-target mapping.
public struct ImportGraph: Sendable, Hashable {
  /// One target of the package with the edges in and out of it.
  public struct Target: Sendable, Hashable {
    /// The SwiftPM target name.
    public let name: String

    /// The package targets with an import edge to this target.
    public let importedBy: [String]

    /// The package targets at the outgoing ends of this target's import edges.
    public let imports: [String]

    /// Creates a target with its incoming and outgoing import edges.
    public init(name: String, importedBy: [String], imports: [String]) {
      self.name = name
      self.importedBy = importedBy
      self.imports = imports
    }

    /// The target's instability, from 0 to 1.
    ///
    /// Instability is the count of ``imports`` divided by the count across
    /// both edge lists, as defined by the stable dependencies principle. A
    /// target without outgoing imports has value 0. With outgoing imports and
    /// no incoming ones, the value is 1.
    ///
    /// A dependency should point at a target with a lower value.
    public var instability: Double {
      let total = imports.count + importedBy.count
      guard total > 0 else { return 0 }
      return Double(imports.count) / Double(total)
    }
  }

  /// The package's targets, in declaration order.
  public let targets: [Target]

  /// Manifest expressions that kept the graph from covering every target.
  public let unresolvedManifestValues: [PackageManifest.UnresolvedValue]

  /// Whether the graph covers every target and source selection.
  public var isComplete: Bool { unresolvedManifestValues.isEmpty }

  /// Creates a graph from targets in package declaration order.
  public init(
    targets: [Target],
    unresolvedManifestValues: [PackageManifest.UnresolvedValue] = []
  ) {
    self.targets = targets
    self.unresolvedManifestValues = unresolvedManifestValues
  }
}

extension ImportGraph.Target: CustomStringConvertible {
  public var description: String {
    "\(name) (imports \(imports.count), imported by \(importedBy.count))"
  }
}

extension Codebase {
  /// Returns the imports between the targets of the package.
  ///
  /// A target with no source files in the codebase has no recorded imports.
  ///
  /// - Throws: ``CodebaseError`` when project root resolution or source
  ///   parsing fails.
  public func importGraph() async throws(CodebaseError) -> ImportGraph {
    let analysis = try await packageAnalysis()
    let names = analysis.targets.map(\.name)
    let ignoredTargets: Set<String> = []
    return ImportGraph(
      targets: names.map { name in
        let importedBy = Set(analysis.importers(
          of: name,
          ignoring: ignoredTargets
        ))
        let imports = Set(analysis.imports(
          from: name,
          ignoring: ignoredTargets
        ))
        return ImportGraph.Target(
          name: name,
          importedBy: names.filter(importedBy.contains),
          imports: names.filter(imports.contains)
        )
      },
      unresolvedManifestValues: analysis.unresolvedDependencyGraphValues
    )
  }
}
