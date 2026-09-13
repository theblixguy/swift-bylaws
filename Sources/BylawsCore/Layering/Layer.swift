/// One named layer of a codebase's architecture.
public struct Layer: Sendable, Hashable {
  /// What a layer may import.
  ///
  /// ``only(_:)`` treats its names as an allow-list. Imports of unnamed layers
  /// violate the policy. Use ``any`` without an allow-list, and declare
  /// individual bans with `mustNotImport`.
  public enum ImportPolicy: Sendable, Hashable, ExpressibleByArrayLiteral {
    /// The layer may import only the named layers.
    case only([String])

    /// The layer may import any layer.
    case any

    /// Creates an allow-list from an array literal of layer names.
    public init(arrayLiteral elements: String...) {
      self = .only(elements)
    }

    /// The named layers, or `nil` when the layer may import any layer.
    public var allowedLayers: [String]? {
      switch self {
      case let .only(names): names
      case .any: nil
      }
    }

    /// Checks whether the layer may import `layerName`.
    public func allows(_ layerName: String) -> Bool {
      switch self {
      case let .only(names): names.contains(layerName)
      case .any: true
      }
    }
  }

  /// The layer's name, such as `"Domain"`.
  public let name: String

  /// The globs that locate the layer's files.
  public let files: [Glob]

  /// The module names an import of this layer uses.
  public let modules: [String]

  /// The policy that decides which layers this layer may import.
  public let importPolicy: ImportPolicy

  /// The names of the layers this layer must import in at least one file.
  public let requiredImports: [String]

  /// The names of the layers this layer forbids.
  public let forbiddenImports: [String]

  /// Creates a layer from its name, its file globs and the layers it
  /// may import.
  ///
  /// By default, `modules` contains the layer's name. A one-target layer with
  /// the same module name needs no explicit modules. Every `mustImport` layer
  /// is also allowed. The check fails when no file uses that edge. An
  /// import of a `mustNotImport` layer is a violation even when `mayImport`
  /// is ``ImportPolicy/any``.
  public init(
    _ name: String,
    files: [Glob],
    modules: [String]? = nil,
    mayImport importPolicy: ImportPolicy = [],
    mustImport requiredImports: [String] = [],
    mustNotImport forbiddenImports: [String] = []
  ) {
    self.name = name
    self.files = files
    self.modules = modules ?? [name]
    self.importPolicy = importPolicy
    self.requiredImports = requiredImports
    self.forbiddenImports = forbiddenImports
  }

  /// The names of the layers this layer may import, or `nil` when the
  /// layer may import any layer.
  public var allowedImports: [String]? { importPolicy.allowedLayers }
}
