extension SourceSlice {
  /// Returns whether a physical source line touched by this slice exceeds the width.
  ///
  /// Measures complete original file lines, including text before and after
  /// the slice. Each Swift character occupies one column. Tabs advance to the
  /// next tab stop, with nonpositive tab widths treated as one column.
  /// LF, CRLF and CR separate lines and do not contribute to the width.
  /// A line ending belongs to the preceding line. An empty slice touches no
  /// lines and returns `false`.
  public func hasLine(
    exceeding maximumWidth: Int,
    tabWidth: Int = 8
  ) -> Bool {
    guard !range.isEmpty else { return false }
    let bytes = snapshot.text.utf8
    let start = bytes.index(bytes.startIndex, offsetBy: range.lowerBound)
    let end = bytes.index(bytes.startIndex, offsetBy: range.upperBound)
    var lineStart = start
    if bytes[lineStart] == 0x0A, lineStart > bytes.startIndex {
      let previous = bytes.index(before: lineStart)
      if bytes[previous] == 0x0D { lineStart = previous }
    }
    while lineStart > bytes.startIndex {
      let previous = bytes.index(before: lineStart)
      guard bytes[previous] != 0x0A, bytes[previous] != 0x0D else { break }
      lineStart = previous
    }
    while lineStart < end {
      var lineEnd = lineStart
      while lineEnd < bytes.endIndex,
            bytes[lineEnd] != 0x0A, bytes[lineEnd] != 0x0D
      {
        bytes.formIndex(after: &lineEnd)
      }
      let text = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
      if SourceTextWidth.exceeds(maximumWidth, in: text, tabWidth: tabWidth) {
        return true
      }
      guard lineEnd < end else { return false }
      let isCR = bytes[lineEnd] == 0x0D
      bytes.formIndex(after: &lineEnd)
      if isCR, lineEnd < bytes.endIndex, bytes[lineEnd] == 0x0A {
        bytes.formIndex(after: &lineEnd)
      }
      lineStart = lineEnd
    }
    return false
  }
}
