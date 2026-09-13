package final class SourceBuffer: Sendable {
  package let text: String
  package let lineCount: Int

  package init(_ text: String) {
    self.text = text
    lineCount = Self.lineCount(in: text)
  }

  package init(_ text: String, lineCount: Int) {
    self.text = text
    self.lineCount = lineCount
  }

  package func contains(_ range: Range<Int>) -> Bool {
    range.lowerBound >= 0 && range.upperBound <= text.utf8.count
  }

  package func text(inUTF8Range range: Range<Int>) -> String {
    guard contains(range) else { return "" }
    let utf8 = text.utf8
    let lowerBound = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
    let upperBound = utf8.index(utf8.startIndex, offsetBy: range.upperBound)
    return String(decoding: utf8[lowerBound..<upperBound], as: UTF8.self)
  }

  private static func lineCount(in text: String) -> Int {
    guard !text.isEmpty else { return 0 }
    var count = 1
    var previousWasCarriageReturn = false
    for byte in text.utf8 {
      if byte == UInt8(ascii: "\r") {
        count += 1
      } else if byte == UInt8(ascii: "\n"), !previousWasCarriageReturn {
        count += 1
      }
      previousWasCarriageReturn = byte == UInt8(ascii: "\r")
    }
    return count
  }
}
