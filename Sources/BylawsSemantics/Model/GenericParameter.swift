/// One parameter of a declaration's generic clause.
public struct GenericParameter: Sendable, Hashable, Codable {
  /// The parameter's name, such as `T`.
  public let name: String

  /// The constraint written in the clause, such as `Codable` in
  /// `<T: Codable>`, or `nil` for an unconstrained parameter.
  public let constraintName: String?

  /// Creates a generic-parameter model.
  public init(name: String, constraintName: String? = nil) {
    self.name = name
    self.constraintName = constraintName
  }
}
