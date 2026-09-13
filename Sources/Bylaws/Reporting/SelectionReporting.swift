#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  extension Selection {
    /// Checks every element in the selection against `matcher` and returns
    /// the violations.
    ///
    /// The check records a non-failing issue for a selection that matches no
    /// declarations.
    public func violations(
      of matcher: Matcher<Element>,
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      if isEmpty {
        Issue.recordWarning(
          "Query '\(queryDescription)' matched no declarations. Check the query.",
          sourceLocation: sourceLocation
        )
      }
      return Violations(of: matcher, in: self)
    }

    /// Checks every element in the selection and returns the elements that
    /// match `matcher` as the violations.
    ///
    /// Use this for a ban, where matching is the violation:
    ///
    /// ```swift
    /// files.violations(matching: .imports("UIKit") || .imports("SwiftUI"))
    /// ```
    public func violations(
      matching matcher: Matcher<Element>,
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      violations(of: !matcher, sourceLocation: sourceLocation)
    }
  }
#endif
