package import BylawsSemantics

extension NominalTypeStorage: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      inheritedTypes: try decoder.decode(),
      genericParameters: try decoder.decode(),
      source: decoder.source,
      sourceRange: try decoder.decode(),
      isNonisolated: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
    guard source.contains(sourceRange) else { throw CacheDecoder.Malformed() }
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(inheritedTypes)
    encoder.encode(genericParameters)
    encoder.encode(sourceRange)
    encoder.encode(isNonisolated)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(enclosingTypeName)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}

extension Class: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(storage: try decoder.decode(), isFinal: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(storage)
    encoder.encode(isFinal)
  }
}

extension Actor: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(storage: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(storage)
  }
}

extension Struct: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(storage: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(storage)
  }
}

extension Enum: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(storage: try decoder.decode(), isIndirect: try decoder.decode())
    cases = try decoder.decode()
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(storage)
    encoder.encode(isIndirect)
    encoder.encode(cases)
  }
}

extension EnumCase: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      isIndirect: try decoder.decode(),
      rawValue: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(isIndirect)
    encoder.encode(rawValue)
    encoder.encode(enclosingTypeName)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}

extension ProtocolDeclaration: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      inheritedTypes: try decoder.decode(),
      source: decoder.source,
      sourceRange: try decoder.decode(),
      isNonisolated: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
    guard source.contains(sourceRange) else { throw CacheDecoder.Malformed() }
    requiredFunctions = try decoder.decode()
    requiredProperties = try decoder.decode()
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(inheritedTypes)
    encoder.encode(sourceRange)
    encoder.encode(isNonisolated)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(documentation)
    encoder.encode(location)
    encoder.encode(requiredFunctions)
    encoder.encode(requiredProperties)
  }
}
