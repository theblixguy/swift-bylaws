extension SourceLayoutReplacement {
  struct Context {
    let bytes: [UInt8]
    let lineEnding: String
    let indentationUnit: String

    init(
      snapshot: SourceSnapshot,
      bytes: [UInt8],
      excluding range: Range<Int>,
      lineEnding: String? = nil
    ) {
      self.bytes = bytes
      self.lineEnding = lineEnding ?? snapshot.lineEnding
      indentationUnit = Self.indentationUnit(in: bytes, excluding: range)
    }

    func indentation(before offset: Int) -> String {
      SourceLayoutText.indentation(in: bytes, before: offset)
    }

    func column(before offset: Int) -> Int {
      let start = lineStart(before: offset)
      return String(decoding: bytes[start..<offset], as: UTF8.self)
        .reduce(0) { column, character in
          character == "\t" ? column + 8 - column % 8 : column + 1
        }
    }

    private func lineStart(before offset: Int) -> Int {
      var start = offset
      while start > 0, bytes[start - 1] != 10, bytes[start - 1] != 13 {
        start -= 1
      }
      return start
    }

    private static func indentationUnit(
      in bytes: [UInt8], excluding range: Range<Int>
    ) -> String {
      var startsLine = true
      for byte in bytes {
        if startsLine, byte == 9 { return "\t" }
        startsLine = byte == 10 || byte == 13
      }
      // The edited list can change the inferred unit on the next run.
      var smallest: Int?
      for region in [0..<range.lowerBound, range.upperBound..<bytes.count] {
        var index = region.lowerBound
        while index < region.upperBound {
          let start = index
          while index < region.upperBound, bytes[index] == 32 { index += 1 }
          let count = index - start
          if count > 0 { smallest = min(smallest ?? count, count) }
          while index < region.upperBound, bytes[index] != 10,
                bytes[index] != 13 { index += 1 }
          if index < region.upperBound { index += 1 }
        }
      }
      return String(repeating: " ", count: smallest ?? 2)
    }
  }
}
