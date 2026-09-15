public import BylawsSemantics

/// The configured targets and dependencies from a Bazel query.
///
/// Load a query with ``Codebase/bazelGraph(from:)``. Targets with the same
/// label in different configurations remain separate.
public struct BazelGraph: Sendable, Equatable {
  /// A build target, file or package group in the query result.
  public struct Target: Sendable, Hashable, Located, CustomStringConvertible {
    /// The full Bazel label, including the repository for an external target.
    public let label: String

    /// The build configuration, or `nil` for an unconfigured target.
    public let configuration: Configuration?

    /// The Bazel rule class, such as `swift_library`, or `nil` for a file or package group.
    public let ruleClass: String?

    /// The tags assigned to the target.
    public let tags: [String]

    /// The target's source position, or the export file when Bazel omits it.
    public let location: DeclarationLocation

    /// The target's label.
    public var description: String { label }

    var key: Key { Key(label: label, configuration: configuration?.checksum) }
  }

  /// The targets, ordered by label and configuration checksum.
  public let targets: [Target]

  private let indices: [Key: Int]
  private let graph: OrderedDirectedGraph<Int>

  init(targets: [Target], indices: [Key: Int], edges: [DirectedEdge<Int>]) {
    self.targets = targets
    self.indices = indices
    graph = OrderedDirectedGraph(nodes: Array(targets.indices), edges: edges)
  }

  /// Returns the immediate dependencies of `target` in query order.
  ///
  /// The result includes file and tool dependencies present in the export.
  public func directTargetDependencies(of target: Target) -> [Target] {
    guard let index = indices[target.key] else { return [] }
    return graph.successors(of: index).map { targets[$0] }
  }

  /// Returns each reachable dependency once, with nearer dependencies first.
  ///
  /// The result excludes `target` itself and keeps build configurations separate.
  public func transitiveTargetDependencies(of target: Target) -> [Target] {
    guard let index = indices[target.key] else { return [] }
    return graph.reachable(from: [index]).map { targets[$0] }
  }

  /// Returns whether both graphs contain the same targets and dependencies.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.targets == rhs.targets && lhs.targets.indices.allSatisfy {
      lhs.graph.successors(of: $0) == rhs.graph.successors(of: $0)
    }
  }

  struct Key: Hashable, Sendable {
    let label: String
    let configuration: String?
  }
}
