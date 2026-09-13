/// One parameter of a function or initialiser.
public struct Parameter: Sendable, Hashable, Codable {
  /// The external argument label, or `nil` when the label is `_`.
  public let label: String?

  /// The internal parameter name.
  public let name: String

  /// The parameter's type.
  public let type: TypeReference

  /// The parameter's type, as written.
  public var typeName: String { type.text }

  /// Creates a parameter model.
  public init(label: String?, name: String, type: TypeReference) {
    self.label = label
    self.name = name
    self.type = type
  }
}
