package struct ParsedSource: Sendable {
  package let whole: SourceSlice
  package var name: SourceSlice?
  package var body: SourceSlice?
  package var calledExpression: SourceSlice?
  package var memberName: SourceSlice?

  package init(
    whole: SourceSlice, name: SourceSlice? = nil, body: SourceSlice? = nil,
    calledExpression: SourceSlice? = nil, memberName: SourceSlice? = nil
  ) {
    self.whole = whole
    self.name = name
    self.body = body
    self.calledExpression = calledExpression
    self.memberName = memberName
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
