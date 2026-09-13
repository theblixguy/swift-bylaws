#if canImport(Testing)
  public import BylawsSemantics
  @_weakLinked public import Testing

  extension CustomTestStringConvertible where Self: CustomStringConvertible {
    public var testDescription: String { description }
  }

  private enum DeclarationCodingKeys: String, CodingKey {
    case file
    case name
  }

  extension CustomTestArgumentEncodable where Self: Located & Named {
    /// Encodes the declaration's file name and name as the argument's
    /// identity.
    ///
    /// A rerun of a failed test case selects the same declaration after
    /// unrelated edits move it.
    ///
    /// - Parameter encoder: The encoder the testing library supplies.
    public func encodeTestArgument(to encoder: some Encoder) throws {
      var container = encoder.container(keyedBy: DeclarationCodingKeys.self)
      try container.encode(location.fileName, forKey: .file)
      try container.encode(name, forKey: .name)
    }
  }

  extension Class: CustomTestStringConvertible, CustomTestArgumentEncodable {}

  extension Actor: CustomTestStringConvertible, CustomTestArgumentEncodable {}

  extension Struct: CustomTestStringConvertible, CustomTestArgumentEncodable {}

  extension Enum: CustomTestStringConvertible, CustomTestArgumentEncodable {}

  extension ProtocolDeclaration: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension Function: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension Property: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension SourceFile: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension Initializer: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension EnumCase: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension Import: CustomTestStringConvertible, CustomTestArgumentEncodable {}

  extension Extension: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension FunctionCall: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}

  extension Typealias: CustomTestStringConvertible,
    CustomTestArgumentEncodable {}
#endif
