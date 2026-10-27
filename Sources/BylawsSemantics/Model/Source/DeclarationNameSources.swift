extension Function {
  /// The function identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension Property {
  /// The binding identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension Initializer {
  /// The `init` keyword.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension Import {
  /// The imported module path.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension Typealias {
  /// The alias identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension ProtocolDeclaration {
  /// The protocol identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension Extension {
  /// The extended type as written.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension EnumCase {
  /// The case identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws { try parsedSource.required().name.required(or: .missingPart) }
  }
}

extension FunctionCall {
  /// The called expression as written.
  public var nameSource: SourceSlice {
    get throws {
      try parsedSource.required().calledExpression.required(or: .missingPart)
    }
  }
}
