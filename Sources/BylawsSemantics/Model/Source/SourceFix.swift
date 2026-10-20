/// A proposed correction whose edits apply together.
public struct SourceFix: Sendable, Hashable, Codable {
  /// The description of the correction, when supplied.
  public let title: String?

  /// The replacements against the original source snapshots.
  public let edits: [Edit]

  /// Creates a correction from its replacements.
  public init(_ title: String? = nil, edits: [Edit]) {
    self.title = title
    self.edits = edits
  }

  /// One replacement against an original source snapshot.
  public struct Edit: Sendable, Hashable, Codable {
    /// The original source to replace.
    public let source: SourceSlice

    /// The text to write in place of the original source.
    public let replacement: String

    package init(source: SourceSlice, replacement: String) {
      self.source = source
      self.replacement = replacement
    }

    /// Compares the source spans and exact replacement bytes.
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.source == rhs.source
        && lhs.replacement.utf8.elementsEqual(rhs.replacement.utf8)
    }

    /// Hashes the source span and exact replacement bytes.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(source)
      for byte in replacement.utf8 { hasher.combine(byte) }
    }
  }
}
