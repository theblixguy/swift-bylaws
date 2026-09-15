import BylawsCore
import BylawsSemantics

extension CompilationBranch: MatcherSubject {
  static var family: SupportedAPI.DeclarationFamily { .compilationBranch }

  static func matcher(
    _ resolved: MatcherCompiler.ResolvedMatcher,
    _ call: ParsedCall
  ) -> Matcher<Self>? {
    MatcherCompiler.named(resolved, call)
  }
}
