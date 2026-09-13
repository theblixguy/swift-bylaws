import BylawsCore
import BylawsSemantics

enum MatcherCompiler {
  struct ResolvedMatcher {
    let id: SupportedAPI.Matcher.ID
    let namePattern: NamePattern?
  }

  static func resolve(
    _ call: ParsedCall,
    for declarationFamily: SupportedAPI.DeclarationFamily
  ) -> Result<ResolvedMatcher, Diagnostic> {
    guard let matcher = SupportedAPI.matcher(named: call.name) else {
      return .failure(
        .error(
          "'\(call.name)' is not a matcher",
          at: call.location,
          hint: "matchers are "
            + SupportedAPI.matchers.map(\.name).joined(separator: ", ")
        )
      )
    }
    guard call.accepts(matcher.arguments) else {
      return .failure(
        .error(
          "'\(call.name)' \(matcher.arguments.requirement)",
          at: call.location
        )
      )
    }
    let namePattern: NamePattern?
    if matcher.id == .nameMatching {
      guard let pattern = call.unlabelledStrings.first else {
        return .failure(
          .error(
            "'\(call.name)' \(matcher.arguments.requirement)",
            at: call.location
          )
        )
      }
      do {
        namePattern = try NamePattern(pattern)
      } catch {
        return .failure(
          .error(error.description, at: call.location)
        )
      }
    } else {
      namePattern = nil
    }
    guard matcher.declarationFamilies.contains(declarationFamily) else {
      return .failure(
        .error(
          "'\(call.name)' does not apply to this query's "
            + "declarations",
          at: call.location
        )
      )
    }
    return .success(
      ResolvedMatcher(id: matcher.id, namePattern: namePattern)
    )
  }

  static func named<Subject: Named>(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    let strings = call.unlabelledStrings
    return switch matcher.id {
    case .named: .named(strings)
    case .suffixed: .suffixed(strings)
    case .prefixed: .prefixed(strings)
    case .nameMatching: matcher.namePattern.map(Matcher.nameMatching)
    default: nil
    }
  }

  static func inheritance<Subject: InheritanceProviding>(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    switch id {
    case .inherits: .inherits(from: call.strings(startingWith: .from))
    case .directlyInherits:
      .directlyInherits(from: call.strings(startingWith: .from))
    case .conforms: .conforms(to: call.strings(startingWith: .to))
    case .directlyConforms:
      .directlyConforms(to: call.strings(startingWith: .to))
    case .declaresInheritance:
      call.unlabelledStrings.first.map { .declaresInheritance($0) }
    default: nil
    }
  }

  static func visible<Subject: Visible>(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    switch id {
    case .isPublic: .isPublic
    case .hasVisibility:
      call.member(labelled: .atLeast)
        .flatMap { Visibility(rawValue: $0) }
        .map { .hasVisibility(atLeast: $0) }
    default: nil
    }
  }

  static func attributed<Subject: Attributed>(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    switch id {
    case .hasAttribute: .hasAttribute(call.unlabelledStrings)
    default: nil
    }
  }

  static func documented<Subject: Documented>(
    _ id: SupportedAPI.Matcher.ID
  ) -> Matcher<Subject>? {
    switch id {
    case .hasDocumentation: .hasDocumentation
    default: nil
    }
  }

  static func type<
    Subject: Named & InheritanceProviding & Visible & Attributed & Documented
  >(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    named(matcher, call) ?? inheritance(matcher.id, call)
      ?? visible(matcher.id, call)
      ?? attributed(matcher.id, call) ?? documented(matcher.id)
  }

  static func member<
    Subject: Named & Visible & Attributed & Documented
  >(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Subject>? {
    named(matcher, call) ?? visible(matcher.id, call)
      ?? attributed(matcher.id, call) ?? documented(matcher.id)
  }

  static func `extension`(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Extension>? {
    named(matcher, call) ?? visible(matcher.id, call)
      ?? attributed(matcher.id, call)
  }

  static func `typealias`(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Typealias>? {
    named(matcher, call) ?? visible(matcher.id, call)
      ?? attributed(matcher.id, call) ?? documented(matcher.id)
  }

  static func `class`(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Class>? {
    switch id {
    case .isFinal: .isFinal
    default: nil
    }
  }

  static func `enum`(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Enum>? {
    switch id {
    case .isIndirect: .isIndirect
    default: nil
    }
  }

  static func nominalType(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<NominalType>? {
    switch id {
    case .isClass: .isClass
    case .isStruct: .isStruct
    case .isEnum: .isEnum
    case .isActor: .isActor
    default: nil
    }
  }

  static func file(
    _ matcher: ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<SourceFile>? {
    switch matcher.id {
    case .imports: .imports(call.unlabelledStrings)
    case .calls: .calls(call.unlabelledStrings)
    default: named(matcher, call)
    }
  }

  static func function(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Function>? {
    switch id {
    case .calls: .calls(call.unlabelledStrings)
    case .isOverride: .isOverride
    case .isMutating: .isMutating
    case .isDynamic: .isDynamic
    case .isAsync: .isAsync
    case .isThrowing: .isThrowing
    case .isNonisolated: .isNonisolated
    case .returnsOptional: .returnsOptional
    case .returns: call.unlabelledStrings.first.map { .returns($0) }
    case .hasParameter: functionParameter(call)
    default: nil
    }
  }

  static func property(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Property>? {
    switch id {
    case .calls: .calls(call.unlabelledStrings)
    case .isWeak: .isWeak
    case .isLazy: .isLazy
    case .isDynamic: .isDynamic
    case .isNonisolated: .isNonisolated
    case .isNonisolatedUnsafe: .isNonisolatedUnsafe
    case .hasOptionalType: .hasOptionalType
    case .hasType: .hasType(call.unlabelledStrings)
    case .referencesType: .referencesType(call.unlabelledStrings)
    default: nil
    }
  }

  static func initializer(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<Initializer>? {
    switch id {
    case .isConvenience: .isConvenience
    default: nil
    }
  }

  static func call(
    _ id: SupportedAPI.Matcher.ID,
    _ call: ParsedCall
  ) -> Matcher<FunctionCall>? {
    switch id {
    case .references: .references(call.unlabelledStrings)
    case .hasArgumentLabel:
      call.unlabelledStrings.first.map { .hasArgumentLabel($0) }
    default: nil
    }
  }

  private static func functionParameter(
    _ call: ParsedCall
  ) -> Matcher<Function> {
    if let type = call.strings(labelled: .typed).first {
      return .hasParameter(typed: type)
    }
    if let label = call.strings(labelled: .labelled).first {
      return .hasParameter(labelled: label)
    }
    return .hasParameter(
      referencing: call.strings(startingWith: .referencing)
    )
  }
}
