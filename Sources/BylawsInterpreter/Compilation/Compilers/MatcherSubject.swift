import BylawsCore
import BylawsSemantics

protocol MatcherSubject: Named, Sendable {
  static var family: SupportedAPI.DeclarationFamily { get }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>?
}

extension MatcherSubject {
  static func requirement(
    of resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> String? {
    matcher(resolved, call)?.requirementDescription
  }

  func match(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> (matches: Bool, witness: DeclarationLocation?)? {
    guard let matcher = Self.matcher(resolved, call) else { return nil }
    let result = matcher.match(self)
    return (result.matches, result.witness)
  }
}

extension SourceFile: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .file }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.file(resolved, call)
  }
}

extension Class: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .class }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
      ?? MatcherCompiler.class(resolved.id, call)
  }
}

extension Actor: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .actor }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
  }
}

extension Struct: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .struct }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
  }
}

extension Enum: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .enum }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
      ?? MatcherCompiler.enum(resolved.id, call)
  }
}

extension NominalType: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .nominalType }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
      ?? MatcherCompiler.nominalType(resolved.id, call)
  }
}

extension ProtocolDeclaration: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .protocol }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.type(resolved, call)
  }
}

extension Extension: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .extension }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.extension(resolved, call)
  }
}

extension Function: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .function }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.member(resolved, call)
      ?? MatcherCompiler.function(resolved.id, call)
  }
}

extension Property: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .property }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.member(resolved, call)
      ?? MatcherCompiler.property(resolved.id, call)
  }
}

extension Initializer: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .initializer }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.member(resolved, call)
      ?? MatcherCompiler.initializer(resolved.id, call)
  }
}

extension Import: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .import }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
      ?? MatcherCompiler.visible(resolved.id, call)
      ?? MatcherCompiler.attributed(resolved.id, call)
  }
}

extension Typealias: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .typealias }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.typealias(resolved, call)
  }
}

extension FunctionCall: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .functionCall }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
      ?? MatcherCompiler.call(resolved.id, call)
  }
}

extension SupportedAPI.DeclarationFamily {
  var subject: any MatcherSubject.Type {
    switch self {
    case .file: SourceFile.self
    case .class: Class.self
    case .actor: Actor.self
    case .struct: Struct.self
    case .enum: Enum.self
    case .nominalType: NominalType.self
    case .protocol: ProtocolDeclaration.self
    case .extension: Extension.self
    case .function: Function.self
    case .property: Property.self
    case .initializer: Initializer.self
    case .import: Import.self
    case .typealias: Typealias.self
    case .functionCall: FunctionCall.self
    case .sourceExpression: SourceExpression.self
    }
  }
}

extension RuntimeModelValue {
  var matcherSubject: (any MatcherSubject)? {
    switch self {
    case let .sourceFile(value): value
    case let .classDeclaration(value): value
    case let .actor(value): value
    case let .structDeclaration(value): value
    case let .enumDeclaration(value): value
    case let .nominalType(value): value
    case let .protocolDeclaration(value): value
    case let .extensionDeclaration(value): value
    case let .function(value): value
    case let .property(value): value
    case let .initializer(value): value
    case let .importDeclaration(value): value
    case let .typealiasDeclaration(value): value
    case let .functionCall(value): value
    case let .sourceExpression(value): value
    case .callArgument, .expressionArgument,
         .dictionaryElement,
         .check, .typeReference, .parameter, .attribute, .genericParameter,
         .enumCase, .importGraph, .importGraphTarget, .bazelGraph, .bazelTarget,
         .bazelConfiguration,
         .packageManifest,
         .manifest, .indexReference, .indexSymbol, .offender, .syntaxClass,
         .syntaxMemberBlock, .syntaxSourceFile, .syntaxToken,
         .syntaxTriviaPiece:
      nil
    }
  }

  var family: SupportedAPI.DeclarationFamily? {
    matcherSubject.map { type(of: $0).family }
  }
}
