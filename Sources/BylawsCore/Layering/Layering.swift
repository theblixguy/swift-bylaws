import BylawsSemantics

/// The allowed import edges between the layers of a codebase.
///
/// Declare each layer with the layers it may import. An import outside
/// those edges is a violation. A file may always import its own layer or
/// a module that no layer declares.
///
/// Import checks expect each layer to own a different module. Index-backed
/// checks may use file globs for layers inside one module.
public struct Layering: Sendable, Hashable {
  /// The declared layers, in declaration order.
  public let layers: [Layer]

  /// Creates a layering from its layers.
  public init(_ layers: Layer...) {
    self.layers = layers
  }

  /// Creates a layering from an array of layers.
  public init(_ layers: [Layer]) {
    self.layers = layers
  }

  /// Creates a layering with expressions, conditions and loops.
  public init(@ArrayBuilder<Layer> _ body: () -> [Layer]) {
    layers = body()
  }

  package func declaredCycle() -> [String]? {
    OrderedDirectedGraph(
      nodes: layers.map(\.name),
      edges: layers.flatMap { layer in
        ((layer.allowedImports ?? []) + layer.requiredImports)
          .filter { $0 != layer.name }
          .map { DirectedEdge(from: layer.name, to: $0) }
      }
    ).firstCycle()
  }
}
