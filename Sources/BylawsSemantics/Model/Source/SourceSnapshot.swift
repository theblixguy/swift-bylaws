import BylawsSyntax

/// The complete source text against which a correction was prepared.
public struct SourceSnapshot: Sendable, Codable, Hashable {
  /// The source file's path.
  public var filePath: String { storage.filePath }

  /// The source file's text.
  public var text: String { storage.text }

  /// The language mode used to parse the source.
  public var swiftLanguageMode: SwiftLanguageMode { storage.swiftLanguageMode }

  private let storage: Storage

  var syntaxContext: SourceSyntaxContext? { storage.syntaxContext }

  var parsedTree: SourceFileSyntax? { syntaxContext?.tree }

  package var lineEnding: String {
    if let syntaxContext { return syntaxContext.lineEnding }
    return if text.contains("\r\n") {
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
    var hasher = Hasher()
    hasher.combine(text)
    self.init(
      filePath: filePath, text: text, swiftLanguageMode: swiftLanguageMode,
      textFingerprint: hasher.finalize(), syntaxContext: nil
    )
  }

  private init(
    filePath: String, text: String, swiftLanguageMode: SwiftLanguageMode,
    textFingerprint: Int, syntaxContext: SourceSyntaxContext?
  ) {
    storage = Storage(
      filePath: filePath, text: text, swiftLanguageMode: swiftLanguageMode,
      textFingerprint: textFingerprint, syntaxContext: syntaxContext
    )
  }

  func withSyntaxTree(_ tree: SourceFileSyntax) -> Self {
    Self(
      filePath: filePath, text: text, swiftLanguageMode: swiftLanguageMode,
      textFingerprint: storage.textFingerprint,
      syntaxContext: SourceSyntaxContext(tree: tree, source: self)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case filePath, text, swiftLanguageMode
  }

  /// Decodes a source snapshot.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      filePath: try values.decode(String.self, forKey: .filePath),
      text: try values.decode(String.self, forKey: .text),
      swiftLanguageMode: try values.decode(
        SwiftLanguageMode.self, forKey: .swiftLanguageMode
      )
    )
  }

  /// Encodes the path, source text and language mode.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(filePath, forKey: .filePath)
    try values.encode(text, forKey: .text)
    try values.encode(swiftLanguageMode, forKey: .swiftLanguageMode)
  }

  /// Compares the paths, language modes and exact source bytes.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.storage === rhs.storage { return true }
    guard lhs.filePath == rhs.filePath,
          lhs.swiftLanguageMode == rhs.swiftLanguageMode else { return false }
    // The nested closures keep both buffers alive for the address comparison.
    let sharesStorage = unsafe lhs.text.utf8
      .withContiguousStorageIfAvailable { left in
        unsafe rhs.text.utf8.withContiguousStorageIfAvailable { right in
          unsafe left.count == right.count && left.baseAddress == right
            .baseAddress
        } ?? false
      } ?? false
    return sharesStorage || lhs.text.utf8.elementsEqual(rhs.text.utf8)
  }

  /// Hashes the path, language mode and source text.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(filePath)
    hasher.combine(swiftLanguageMode)
    hasher.combine(storage.textFingerprint)
  }

  private final class Storage: Sendable {
    let filePath: String
    let text: String
    let swiftLanguageMode: SwiftLanguageMode
    let textFingerprint: Int
    let syntaxContext: SourceSyntaxContext?

    init(
      filePath: String, text: String, swiftLanguageMode: SwiftLanguageMode,
      textFingerprint: Int, syntaxContext: SourceSyntaxContext?
    ) {
      self.filePath = filePath
      self.text = text
      self.swiftLanguageMode = swiftLanguageMode
      self.textFingerprint = textFingerprint
      self.syntaxContext = syntaxContext
    }
  }
}

final class SourceSyntaxContext: Sendable {
  let tree: SourceFileSyntax
  let bytes: [UInt8]
  let lineEnding: String

  fileprivate init(tree: SourceFileSyntax, source: SourceSnapshot) {
    self.tree = tree
    bytes = Array(source.text.utf8)
    lineEnding = source.lineEnding
  }
}
