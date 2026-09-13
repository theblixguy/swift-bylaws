public import BylawsSemantics

extension Matcher {
  /// Matches subjects whose selected members all satisfy the matcher.
  ///
  /// An empty collection passes. A failure points to the first member that
  /// fails, or to a more specific location provided by its matcher.
  public static func all<Members: Sequence & SendableMetatype>(
    _ keyPath: any KeyPath<Subject, Members> & Sendable,
    matching matcher: Matcher<Members.Element>
  ) -> Self where Members.Element: Located, Members.Iterator: SendableMetatype {
    Self(criterion: .evaluated(
      "have all selected members \(matcher.requirementDescription)"
    ) { subject in
      for member in subject[keyPath: keyPath] {
        let result = matcher.match(member)
        if !result.matches {
          return Match(
            matches: false,
            witness: result.witness ?? member.location
          )
        }
      }
      return Match(matches: true, witness: nil)
    })
  }

  /// Matches subjects with at least one selected member that satisfies the matcher.
  ///
  /// An empty collection fails. When negated, this matcher reports the first
  /// matching member's location or a more specific location from its matcher.
  public static func any<Members: Sequence & SendableMetatype>(
    _ keyPath: any KeyPath<Subject, Members> & Sendable,
    matching matcher: Matcher<Members.Element>
  ) -> Self where Members.Element: Located, Members.Iterator: SendableMetatype {
    Self(criterion: .evaluated(
      "have any selected members \(matcher.requirementDescription)"
    ) { subject in
      for member in subject[keyPath: keyPath] {
        let result = matcher.match(member)
        if result.matches {
          return Match(
            matches: true,
            witness: result.witness ?? member.location
          )
        }
      }
      return Match(matches: false, witness: nil)
    })
  }

  /// Matches subjects whose selected members never satisfy the matcher.
  ///
  /// An empty collection passes. A failure points to the first matching member
  /// or to a more specific location from its matcher.
  public static func none<Members: Sequence & SendableMetatype>(
    _ keyPath: any KeyPath<Subject, Members> & Sendable,
    matching matcher: Matcher<Members.Element>
  ) -> Self where Members.Element: Located, Members.Iterator: SendableMetatype {
    !any(keyPath, matching: matcher)
  }
}
