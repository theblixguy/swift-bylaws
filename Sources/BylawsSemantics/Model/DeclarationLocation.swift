import BylawsPaths

/// The position of a declaration in a source file.
public struct DeclarationLocation: Sendable, Hashable, Codable {
  /// The absolute path of the source file.
  public package(set) var filePath: String

  /// The line number, starting at 1.
  public let line: Int

  /// The UTF-8 byte column, starting at 1.
  public let column: Int

  /// The UTF-8 byte offset, or `nil` when only the line and column are known.
  public let utf8Offset: Int?

  /// Creates a location from a file path, line, column and byte offset.
  public init(
    filePath: String,
    line: Int,
    column: Int,
    utf8Offset: Int? = nil
  ) {
    self.filePath = filePath
    self.line = line
    self.column = column
    self.utf8Offset = utf8Offset
  }

  package static func start(of path: String) -> Self {
    Self(filePath: path, line: 1, column: 1, utf8Offset: 0)
  }

  package static func callSite(filePath: String, line: Int) -> Self {
    Self(filePath: filePath, line: line, column: 1)
  }

  /// The last path component of the file path.
  public var fileName: String {
    LexicalFilePath(filePath).lastComponent ?? filePath
  }
}
