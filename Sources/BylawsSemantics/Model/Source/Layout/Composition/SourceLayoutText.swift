package struct SourceLayoutText {
  private struct Change {
    let range: Range<Int>
    let count: Int
  }

  package let text: String
  private let changes: [Change]

  package init(
    _ text: String, originalIndentation: String, indentation: String
  ) throws {
    guard originalIndentation != indentation else {
      self.text = text
      changes = []
      return
    }
    let bytes = Array(text.utf8)
    let original = Array(originalIndentation.utf8)
    let replacement = Array(indentation.utf8)
    var changes: [Change] = []
    var result: [UInt8] = []
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      result.append(byte)
      index += 1
      guard byte == 10 || byte == 13 else { continue }
      if byte == 13, index < bytes.count, bytes[index] == 10 {
        result.append(bytes[index])
        index += 1
      }
      guard index < bytes.count, bytes[index] != 10, bytes[index] != 13 else {
        continue
      }
      guard bytes[index...].starts(with: original) else {
        throw SourceLayoutError.inconsistentIndentation
      }
      let end = index + original.count
      changes.append(Change(range: index..<end, count: replacement.count))
      result += replacement
      index = end
    }
    self.text = String(decoding: result, as: UTF8.self)
    self.changes = changes
  }

  package func offset(_ original: Int) throws -> Int {
    var shift = 0
    for change in changes {
      if original < change.range.lowerBound { break }
      if change.range.isEmpty {
        shift += change.count
        continue
      }
      if original == change.range.lowerBound { return original + shift }
      guard original >= change.range.upperBound else {
        throw SourceLayoutError.inconsistentIndentation
      }
      shift += change.count - change.range.count
    }
    return original + shift
  }

  package static func indentation(in text: some StringProtocol) -> String {
    String(text.prefix { $0 == " " || $0 == "\t" })
  }

  package static func indentation(
    in bytes: [UInt8],
    before offset: Int
  ) -> String {
    var start = offset
    while start > 0, bytes[start - 1] != 10, bytes[start - 1] != 13 {
      start -= 1
    }
    return String(
      decoding: bytes[start..<offset].prefix { $0 == 32 || $0 == 9 },
      as: UTF8.self
    )
  }

  package static func lastLine(in text: some StringProtocol) -> Substring {
    let value = String(text)
    let start = value.lastIndex(where: isNewline)
      .map { value.index(after: $0) } ?? value.startIndex
    return value[start...]
  }

  package static func lineSuffix(after source: SourceSlice) -> String {
    String(
      decoding: source.snapshot.text.utf8.dropFirst(source.range.upperBound)
        .prefix { $0 != 10 && $0 != 13 },
      as: UTF8.self
    )
  }

  package static func isNewline(_ character: Character) -> Bool {
    character == "\n" || character == "\r" || character == "\r\n"
  }
}
