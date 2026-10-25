package import BylawsSemantics

extension SourceSlice: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    let range: Range<Int> = try decoder.decode()
    guard let snapshot = decoder.source.snapshot else {
      throw CacheDecoder.Malformed()
    }
    do {
      try self.init(snapshot: snapshot, range: range)
    } catch {
      throw CacheDecoder.Malformed()
    }
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(range)
  }
}

extension ParsedSource: CacheCodable {
  package convenience init(from decoder: CacheDecoder) throws(CacheDecoder
    .Malformed)
  {
    self.init(
      whole: try decoder.decode(),
      name: try decoder.decode(),
      body: try decoder.decode(),
      calledExpression: try decoder.decode(),
      memberName: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(whole)
    encoder.encode(name)
    encoder.encode(body)
    encoder.encode(calledExpression)
    encoder.encode(memberName)
  }
}
