import BylawsSyntax

extension SourceToken {
  /// A token's lexical category, separate from its exact spelling.
  public enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
    /// An arrow in a function type or result clause.
    case arrow
    /// The attribute introducer.
    case atSign
    /// A key-path or string-interpolation introducer.
    case backslash
    /// A backtick delimiter.
    case backtick
    /// An infix operator.
    case binaryOperator
    /// A colon delimiter.
    case colon
    /// A comma delimiter.
    case comma
    /// An implicit closure parameter or projected-value identifier.
    case dollarIdentifier
    /// An ellipsis.
    case ellipsis
    /// An assignment or default-value delimiter.
    case equal
    /// An exclamation mark with a dedicated syntax role.
    case exclamationMark
    /// A floating-point literal.
    case floatLiteral
    /// An identifier.
    case identifier
    /// The question mark of a ternary expression.
    case infixQuestionMark
    /// An integer literal.
    case integerLiteral
    /// A Swift keyword.
    case keyword
    /// An opening generic angle bracket.
    case leftAngle
    /// An opening brace.
    case leftBrace
    /// An opening parenthesis.
    case leftParen
    /// An opening square bracket.
    case leftSquare
    /// A multiline string delimiter.
    case multilineStringQuote
    /// A period delimiter.
    case period
    /// A postfix operator.
    case postfixOperator
    /// A postfix question mark.
    case postfixQuestionMark
    /// A macro introducer.
    case pound
    /// An availability condition introducer.
    case poundAvailable
    /// An alternate conditional-compilation branch.
    case poundElse
    /// A conditional-compilation else-if branch.
    case poundElseif
    /// The end of a conditional-compilation block.
    case poundEndif
    /// A conditional-compilation introducer.
    case poundIf
    /// A source-location directive.
    case poundSourceLocation
    /// An unavailability condition introducer.
    case poundUnavailable
    /// An inout argument introducer.
    case prefixAmpersand
    /// A prefix operator.
    case prefixOperator
    /// The pound delimiter of a raw string.
    case rawStringPoundDelimiter
    /// The pattern text of a regex literal.
    case regexLiteralPattern
    /// The pound delimiter of a regex literal.
    case regexPoundDelimiter
    /// A regex literal's slash delimiter.
    case regexSlash
    /// A closing generic angle bracket.
    case rightAngle
    /// A closing brace.
    case rightBrace
    /// A closing parenthesis.
    case rightParen
    /// A closing square bracket.
    case rightSquare
    /// A semicolon delimiter.
    case semicolon
    /// A script interpreter directive.
    case shebang
    /// A single quote delimiter.
    case singleQuote
    /// A string delimiter.
    case stringQuote
    /// Text inside a string literal.
    case stringSegment
    /// A token category outside those represented by Bylaws.
    case unknown
    /// An underscore pattern.
    case wildcard

    init(_ kind: TokenKind) {
      switch kind {
      case .arrow: self = .arrow
      case .atSign: self = .atSign
      case .backslash: self = .backslash
      case .backtick: self = .backtick
      case .binaryOperator: self = .binaryOperator
      case .colon: self = .colon
      case .comma: self = .comma
      case .dollarIdentifier: self = .dollarIdentifier
      case .ellipsis: self = .ellipsis
      case .equal: self = .equal
      case .exclamationMark: self = .exclamationMark
      case .floatLiteral: self = .floatLiteral
      case .identifier: self = .identifier
      case .infixQuestionMark: self = .infixQuestionMark
      case .integerLiteral: self = .integerLiteral
      case .keyword: self = .keyword
      case .leftAngle: self = .leftAngle
      case .leftBrace: self = .leftBrace
      case .leftParen: self = .leftParen
      case .leftSquare: self = .leftSquare
      case .multilineStringQuote: self = .multilineStringQuote
      case .period: self = .period
      case .postfixOperator: self = .postfixOperator
      case .postfixQuestionMark: self = .postfixQuestionMark
      case .pound: self = .pound
      case .poundAvailable: self = .poundAvailable
      case .poundElse: self = .poundElse
      case .poundElseif: self = .poundElseif
      case .poundEndif: self = .poundEndif
      case .poundIf: self = .poundIf
      case .poundSourceLocation: self = .poundSourceLocation
      case .poundUnavailable: self = .poundUnavailable
      case .prefixAmpersand: self = .prefixAmpersand
      case .prefixOperator: self = .prefixOperator
      case .rawStringPoundDelimiter: self = .rawStringPoundDelimiter
      case .regexLiteralPattern: self = .regexLiteralPattern
      case .regexPoundDelimiter: self = .regexPoundDelimiter
      case .regexSlash: self = .regexSlash
      case .rightAngle: self = .rightAngle
      case .rightBrace: self = .rightBrace
      case .rightParen: self = .rightParen
      case .rightSquare: self = .rightSquare
      case .semicolon: self = .semicolon
      case .shebang: self = .shebang
      case .singleQuote: self = .singleQuote
      case .stringQuote: self = .stringQuote
      case .stringSegment: self = .stringSegment
      case .wildcard: self = .wildcard
      // SwiftSyntax source and binary dependencies expose different token kinds.
      default: self = .unknown
      }
    }
  }
}
