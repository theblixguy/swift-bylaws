extension SourceFile: SourceProviding {
  /// The complete source file, including its trivia.
  public var source: SourceSlice {
    get throws {
      try SourceSlice(
        snapshot: sourceBuffer.snapshot.required(),
        range: 0..<sourceText.utf8.count
      )
    }
  }
}

extension Function: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension Property: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension Initializer: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension Import: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension Typealias: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension ProtocolDeclaration: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension Extension: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension EnumCase: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension FunctionCall: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension FunctionCall.Argument: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension NominalTypeStorage: SourceProviding, ParsedSourceProviding {
  /// The source text represented by this model, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try parsedSource.required().whole }
  }
}

extension VariableBinding: SourceProviding {}
extension SourceAssignment: SourceProviding {}

extension FunctionCall.Argument {
  /// The argument expression, excluding its label and outer trivia.
  public var expressionSource: SourceSlice {
    get throws { try source }
  }

  /// The argument label, or `nil` for an unlabelled argument.
  public var labelSource: SourceSlice? {
    get throws { try parsedSource.required().label }
  }
}

extension NominalTypeDeclaration {
  /// The declaration's source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try storage.parsedSource.required().whole }
  }

  /// The declared identifier, including any backticks.
  public var nameSource: SourceSlice {
    get throws {
      try storage.parsedSource.required().name.required(or: .missingPart)
    }
  }
}

extension FunctionCall {
  /// The called expression, excluding arguments and outer trivia.
  public var calledExpressionSource: SourceSlice {
    get throws {
      try parsedSource.required().calledExpression.required(or: .missingPart)
    }
  }

  /// The final called identifier, including any backticks.
  public var memberNameSource: SourceSlice {
    get throws {
      try parsedSource.required().memberName.required(or: .missingPart)
    }
  }
}

extension SourceNode: SourceProviding {
  /// The node's source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try context.sourceSlice(of: syntax) }
  }
}

extension SourceExpression: SourceProviding {
  /// The expression's source, excluding outer trivia.
  public var source: SourceSlice {
    get throws { try context.sourceSlice(of: syntax) }
  }
}
