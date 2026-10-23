/// A range in one complete source snapshot.
public struct SourceSlice: Sendable, Hashable, Codable {
  package let snapshot: SourceSnapshot

  /// The absolute UTF-8 byte range in the source file.
  public let range: Range<Int>

  /// The path of the source file.
  public var filePath: String { snapshot.filePath }

  /// The text within this slice.
  public var text: String {
    let bytes = snapshot.text.utf8
    let start = bytes.index(bytes.startIndex, offsetBy: range.lowerBound)
    let end = bytes.index(bytes.startIndex, offsetBy: range.upperBound)
    return String(decoding: bytes[start..<end], as: UTF8.self)
  }

  /// The whole source file, including its trivia.
  public var file: Self {
    Self(unchecked: snapshot, range: 0..<snapshot.text.utf8.count)
  }

  package init(snapshot: SourceSnapshot, range: Range<Int>) throws {
    guard Self.contains(range, in: snapshot.text) else {
      throw SourceError.rangeOutOfBounds
    }
    self.init(unchecked: snapshot, range: range)
  }

  private init(unchecked snapshot: SourceSnapshot, range: Range<Int>) {
    self.snapshot = snapshot
    self.range = range
  }

  /// Returns a slice using UTF-8 offsets relative to this slice.
  public func slice(_ relativeUTF8Range: Range<Int>) throws -> Self {
    guard relativeUTF8Range.lowerBound >= 0,
          relativeUTF8Range.upperBound <= range.count
    else { throw SourceError.rangeOutOfBounds }
    return try Self(
      snapshot: snapshot,
      range: (range.lowerBound + relativeUTF8Range.lowerBound)
        ..< (range.lowerBound + relativeUTF8Range.upperBound)
    )
  }

  /// Returns a replacement for this exact slice.
  public func replacement(with text: String) -> SourceFix.Edit {
    SourceFix.Edit(source: self, replacement: text)
  }

  /// Returns the complete regex matches within this slice, in source order.
  public func matches(of regex: Regex<some Any>) -> [Self] {
    let text = text
    return text.matches(of: regex).map { match in
      let lower = text[..<match.range.lowerBound].utf8.count
      let upper = text[..<match.range.upperBound].utf8.count
      return Self(
        unchecked: snapshot,
        range: (range.lowerBound + lower)..<(range.lowerBound + upper)
      )
    }
  }

  private enum CodingKeys: String, CodingKey {
    case snapshot, range
  }

  /// Decodes a source slice and checks its UTF-8 range.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      snapshot: values.decode(SourceSnapshot.self, forKey: .snapshot),
      range: values.decode(Range<Int>.self, forKey: .range)
    )
  }

  private static func contains(_ range: Range<Int>, in text: String) -> Bool {
    guard range.lowerBound >= 0, range.upperBound <= text.utf8.count else {
      return false
    }
    let bytes = text.utf8
    func isBoundary(_ offset: Int) -> Bool {
      guard offset < bytes.count else { return true }
      let index = bytes.index(bytes.startIndex, offsetBy: offset)
      return bytes[index] & 0xC0 != 0x80
    }
    return isBoundary(range.lowerBound) && isBoundary(range.upperBound)
  }
}

extension Collection where Element: SourceProviding {
  /// Returns the collection's single element.
  ///
  /// Throws when the collection is empty or contains more than one element.
  public func only() throws(SourceError) -> Element {
    guard count == 1, let value = first else {
      throw SourceError.matchCount(count)
    }
    return value
  }
}
