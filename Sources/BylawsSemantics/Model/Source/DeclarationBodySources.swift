extension Function {
  /// The function's body contents, excluding braces.
  ///
  /// Throws when the declaration has no body.
  public var bodySource: SourceSlice {
    get throws { try parsedSource.required().body.required(or: .missingPart) }
  }
}

extension Initializer {
  /// The initialiser's body contents, excluding braces.
  ///
  /// Throws when the declaration has no body.
  public var bodySource: SourceSlice {
    get throws { try parsedSource.required().body.required(or: .missingPart) }
  }
}

extension NominalTypeDeclaration {
  /// The member block's contents, excluding braces.
  public var bodySource: SourceSlice {
    get throws {
      try storage.parsedSource.required().body.required(or: .missingPart)
    }
  }
}

extension ProtocolDeclaration {
  /// The requirement block's contents, excluding braces.
  public var bodySource: SourceSlice {
    get throws { try parsedSource.required().body.required(or: .missingPart) }
  }
}

extension Extension {
  /// The member block's contents, excluding braces.
  public var bodySource: SourceSlice {
    get throws { try parsedSource.required().body.required(or: .missingPart) }
  }
}

extension Property {
  /// The accessor block's contents, excluding its outer braces.
  ///
  /// Explicit accessors retain their own braces. Throws for a stored property
  /// without an accessor block.
  public var bodySource: SourceSlice {
    get throws { try parsedSource.required().body.required(or: .missingPart) }
  }
}
