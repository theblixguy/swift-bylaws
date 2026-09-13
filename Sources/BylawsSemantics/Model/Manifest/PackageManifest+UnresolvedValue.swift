extension PackageManifest {
  /// A manifest value that static parsing could not resolve.
  public struct UnresolvedValue: Sendable, Hashable, Codable {
    /// The field that contains the unresolved expression.
    public let field: String

    /// The expression as written in `Package.swift`.
    public let expression: String

    /// The one-based source line, when available.
    public let line: Int?

    /// The one-based source column, when available.
    public let column: Int?

    /// Creates an unresolved-value record.
    public init(
      field: String,
      expression: String,
      line: Int? = nil,
      column: Int? = nil
    ) {
      self.field = field
      self.expression = expression
      self.line = line
      self.column = column
    }
  }
}
