package import BylawsSemantics

extension SourceFile: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      path: decoder.path,
      source: decoder.source,
      imports: try decoder.decode(),
      classes: try decoder.decode(),
      actors: try decoder.decode(),
      structs: try decoder.decode(),
      enums: try decoder.decode(),
      protocols: try decoder.decode(),
      extensions: try decoder.decode(),
      functions: try decoder.decode(),
      properties: try decoder.decode(),
      initializers: try decoder.decode(),
      typealiases: try decoder.decode(),
      macroExpansions: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(path)
    encoder.encode(sourceText)
    encoder.encode(imports)
    encoder.encode(classes)
    encoder.encode(actors)
    encoder.encode(structs)
    encoder.encode(enums)
    encoder.encode(protocols)
    encoder.encode(extensions)
    encoder.encode(functions)
    encoder.encode(properties)
    encoder.encode(initializers)
    encoder.encode(typealiases)
    encoder.encode(macroExpansions)
  }
}

extension DeclarationLocation: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      filePath: decoder.path,
      line: try decoder.decode(),
      column: try decoder.decode(),
      utf8Offset: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(line)
    encoder.encode(column)
    encoder.encode(utf8Offset)
  }
}

extension Visibility: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    let ordinal = try decoder.decodeInt()
    guard Self.allCases.indices.contains(ordinal) else {
      throw CacheDecoder.Malformed()
    }
    self = Self.allCases[ordinal]
  }

  package func encode(to encoder: CacheEncoder) {
    guard let ordinal = Self.allCases.firstIndex(of: self) else {
      preconditionFailure("Unknown visibility: \(rawValue)")
    }
    encoder.encode(ordinal)
  }
}

extension ImportKind: CacheCodable {}

extension Ownership: CacheCodable {}

extension Attribute: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(name: try decoder.decode(), arguments: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(arguments)
  }
}

extension GenericParameter: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(name: try decoder.decode(), constraintName: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(constraintName)
  }
}

extension TypeReference: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      text: try decoder.decode(),
      name: try decoder.decode(),
      genericArguments: try decoder.decode(),
      isOptional: try decoder.decode(),
      isExistential: try decoder.decode(),
      isOpaque: try decoder.decode(),
      isFunction: try decoder.decode(),
      isTuple: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(text)
    encoder.encode(name)
    encoder.encode(genericArguments)
    encoder.encode(isOptional)
    encoder.encode(isExistential)
    encoder.encode(isOpaque)
    encoder.encode(isFunction)
    encoder.encode(isTuple)
  }
}

extension Parameter: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      label: try decoder.decode(),
      name: try decoder.decode(),
      type: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(label)
    encoder.encode(name)
    encoder.encode(type)
  }
}

extension FunctionCall.Argument: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(label: try decoder.decode(), text: try decoder.decode())
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(label)
    encoder.encode(text)
  }
}

extension FunctionCall: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      calledExpression: try decoder.decode(),
      arguments: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(calledExpression)
    encoder.encode(arguments)
    encoder.encode(location)
  }
}

extension Import: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      kind: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(kind)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(location)
  }
}

extension Extension: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      extendedTypeName: try decoder.decode(),
      inheritedTypes: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(extendedTypeName)
    encoder.encode(inheritedTypes)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(location)
  }
}

extension Typealias: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self.init(
      name: try decoder.decode(),
      aliasedTypeName: try decoder.decode(),
      visibility: try decoder.decode(),
      attributes: try decoder.decode(),
      enclosingTypeName: try decoder.decode(),
      documentation: try decoder.decode(),
      location: try decoder.decode()
    )
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(name)
    encoder.encode(aliasedTypeName)
    encoder.encode(visibility)
    encoder.encode(attributes)
    encoder.encode(enclosingTypeName)
    encoder.encode(documentation)
    encoder.encode(location)
  }
}
