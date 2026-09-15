import BylawsCore
import BylawsSemantics

extension SourceExpression: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .sourceExpression }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
  }
}
