/// A syntax error at a position in a source file.
public struct SourceParseDiagnostic: Sendable, Hashable {
  /// The position reported by the parser.
  public let location: DeclarationLocation

  /// The parser's explanation of the error.
  public let message: String

  /// The language mode used for the parse.
  public let swiftLanguageMode: SwiftLanguageMode

  /// Creates a syntax diagnostic at the given location.
  public init(
    location: DeclarationLocation,
    message: String,
    swiftLanguageMode: SwiftLanguageMode
  ) {
    self.location = location
    self.message = message
    self.swiftLanguageMode = swiftLanguageMode
  }
}

extension SourceParseDiagnostic: CustomStringConvertible {
  /// The source position, language mode and parser message.
  public var description: String {
    "\(location.filePath):\(location.line):\(location.column): "
      + "\(message) (Swift \(swiftLanguageMode.rawValue) mode)"
  }
}
