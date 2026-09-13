#if canImport(Testing)
  public import BylawsCore
  @_weakLinked public import Testing

  extension Selection {
    /// Returns violations for elements whose selected Boolean property is false.
    public func violations(
      of keyPath: any KeyPath<Element, Bool> & Sendable,
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      violations(of: Matcher(keyPath), sourceLocation: sourceLocation)
    }

    /// Returns violations for elements whose selected Boolean property is true.
    public func violations(
      matching keyPath: any KeyPath<Element, Bool> & Sendable,
      sourceLocation: SourceLocation = #_sourceLocation
    ) -> Violations<Element> {
      violations(matching: Matcher(keyPath), sourceLocation: sourceLocation)
    }
  }
#endif
