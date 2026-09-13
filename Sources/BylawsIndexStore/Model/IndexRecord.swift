/// A record that holds symbol occurrences for one source file.
public struct IndexRecord: Sendable, Hashable {
  /// The store's identifier for the record.
  public let name: String

  /// The path of the source file whose occurrences the record holds.
  public let file: String

  /// Creates a record with the given store identifier and source path.
  public init(name: String, file: String) {
    self.name = name
    self.file = file
  }
}
