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
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    let range: Range<Int> = try decoder.decode()
    let nameRange: Range<Int>? = try decoder.decode()
    guard decoder.source.containsSourceRange(range) else {
      throw CacheDecoder.Malformed()
    }
    if let nameRange {
      guard !nameRange.isEmpty,
            range.lowerBound <= nameRange.lowerBound,
            nameRange.upperBound <= range.upperBound,
            decoder.source.containsSourceRange(nameRange)
      else {
        throw CacheDecoder.Malformed()
      }
    }
    self.init(buffer: decoder.source, range: range, nameRange: nameRange)
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(range)
    encoder.encode(nameRange)
  }
}
