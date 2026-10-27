package struct ParsedSource: Sendable {
  package let buffer: SourceBuffer
  package let range: Range<Int>
  package let nameRange: Range<Int>?

  package init(
    buffer: SourceBuffer, range: Range<Int>, nameRange: Range<Int>? = nil
  ) {
    self.buffer = buffer
    self.range = range
    self.nameRange = nameRange
  }

  package var whole: SourceSlice {
    get throws {
      try SourceSlice(snapshot: buffer.snapshot.required(), range: range)
    }
  }

  package var name: SourceSlice? {
    get throws {
      try nameRange.map {
        try SourceSlice(snapshot: buffer.snapshot.required(), range: $0)
      }
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
