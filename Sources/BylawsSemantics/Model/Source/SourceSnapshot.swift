/// The complete source text against which a correction was prepared.
public struct SourceSnapshot: Sendable, Codable, Hashable {
  /// The source file's path.
  public let filePath: String

  /// The source file's text.
  public let text: String

  /// The language mode used to parse the source.
  public let swiftLanguageMode: SwiftLanguageMode

  package var lineEnding: String {
    if text.contains("\r\n") {
      "\r\n"
    } else if text.contains("\r"), !text.contains("\n") {
      "\r"
    } else {
      "\n"
    }
  }

  package init(
    filePath: String, text: String, swiftLanguageMode: SwiftLanguageMode
  ) {
    self.filePath = filePath
    self.text = text
    self.swiftLanguageMode = swiftLanguageMode
  }

  /// Compares the paths, language modes and exact source bytes.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.filePath == rhs.filePath
      && lhs.swiftLanguageMode == rhs.swiftLanguageMode
      && lhs.text.utf8.elementsEqual(rhs.text.utf8)
  }

  /// Hashes the path, language mode and exact source bytes.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(filePath)
    hasher.combine(swiftLanguageMode)
    for byte in text.utf8 { hasher.combine(byte) }
  }
}
