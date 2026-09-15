import BylawsCore
import BylawsSemantics

extension SourceAssignment: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .sourceAssignment }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
  }
}

extension VariableBinding: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .variableBinding }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
  }
}
