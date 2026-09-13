package import BylawsSemantics

extension Function: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      source: decoder.source,
      parameters: try decoder.decode(),
      returnType: try decoder.decode(),
      isStatic: try decoder.decode(),
      isOverride: try decoder.decode(),
      isMutating: try decoder.decode(),
      isDynamic: try decoder.decode(),
      isAsync: try decoder.decode(),
      isThrowing: try decoder.decode(),
      isNonisolated: try decoder.decode(),
      genericParameters: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      calls: try decoder.decode(),
      bodyLineCount: try decoder.decode(),
      awaitCount: try decoder.decode(),
      cyclomaticComplexity: try decoder.decode(),
      sourceRange: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
    guard source.contains(sourceRange) else { throw CacheDecoder.Malformed() }
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(parameters)
    encoder.encode(returnType)
    encoder.encode(isStatic)
    encoder.encode(isOverride)
    encoder.encode(isMutating)
    encoder.encode(isDynamic)
    encoder.encode(isAsync)
    encoder.encode(isThrowing)
    encoder.encode(isNonisolated)
    encoder.encode(genericParameters)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(enclosingTypeName)
    encoder.encode(calls)
    encoder.encode(bodyLineCount)
    encoder.encode(awaitCount)
    encoder.encode(cyclomaticComplexity)
    encoder.encode(sourceRange)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}

extension Property: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      type: try decoder.decode(),
      isConstant: try decoder.decode(),
      isStatic: try decoder.decode(),
      ownership: try decoder.decode(),
      isLazy: try decoder.decode(),
      isDynamic: try decoder.decode(),
      isNonisolated: try decoder.decode(),
      isNonisolatedUnsafe: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      calls: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(type)
    encoder.encode(isConstant)
    encoder.encode(isStatic)
    encoder.encode(ownership)
    encoder.encode(isLazy)
    encoder.encode(isDynamic)
    encoder.encode(isNonisolated)
    encoder.encode(isNonisolatedUnsafe)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(enclosingTypeName)
    encoder.encode(calls)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}

extension Initializer: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      parameters: try decoder.decode(),
      isFailable: try decoder.decode(),
      isConvenience: try decoder.decode(),
      isAsync: try decoder.decode(),
      isThrowing: try decoder.decode(),
      isNonisolated: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      calls: try decoder.decode(),
      awaitCount: try decoder.decode(),
      cyclomaticComplexity: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(parameters)
    encoder.encode(isFailable)
    encoder.encode(isConvenience)
    encoder.encode(isAsync)
    encoder.encode(isThrowing)
    encoder.encode(isNonisolated)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(enclosingTypeName)
    encoder.encode(calls)
    encoder.encode(awaitCount)
    encoder.encode(cyclomaticComplexity)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}
