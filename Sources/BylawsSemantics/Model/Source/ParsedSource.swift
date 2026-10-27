package struct ParsedSource: Sendable {
  package let buffer: SourceBuffer
  package let range: Range<Int>

  package init(buffer: SourceBuffer, range: Range<Int>) {
    self.buffer = buffer
    self.range = range
  }

  package var whole: SourceSlice {
    get throws {
      try SourceSlice(snapshot: buffer.snapshot.required(), range: range)
    }
  }
}

package protocol ParsedSourceProviding {
  var parsedSource: ParsedSource? { get set }
}

extension ParsedSourceProviding {
  func withParsedSource(_ source: ParsedSource?) -> Self {
    var copy = self
    copy.parsedSource = source
    return copy
  }
}

extension Optional {
  func required(or error: SourceError = .unavailable) throws(SourceError)
    -> Wrapped
  {
    guard let value = self else { throw error }
    return value
  }
}
