#if canImport(Testing)
  public import BylawsCore
  public import BylawsSemantics
  @_weakLinked public import Testing

  extension Violations where Element: Located {
    /// Records each violation at its declaration and attaches available source fixes.
    ///
    /// The rule ID defaults to the current test's identity.
    /// Reporting leaves source files unchanged.
    ///
    /// In a parameterised test, an inferred ID leaves baseline entries for
    /// other cases unchecked. Pass an explicit ID only when this call reports
    /// a complete rule.
    public func report(
      ruleID: Rule.ID? = nil,
      enforcement: Enforcement = .enforced,
      hint: String? = nil,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      let test = Test.current
      let id = ruleID ?? Rule.ID(test.map { String(describing: $0.id) } ?? rule)
      FindingsReporting.report(
        Rule.Findings(violations: erased()),
        ruleID: id,
        name: rule,
        enforcement: enforcement,
        hint: hint,
        location: DeclarationLocation(
          filePath: sourceLocation.bylawsFilePath,
          line: sourceLocation.line,
          column: sourceLocation.column
        ),
        origin: nil,
        sourceLocation: sourceLocation
      )
      if ruleID != nil || test?.isParameterized != true {
        TraitScope.completedRuleObserver?(id)
      }
    }
  }

  extension SourceLocation {
    fileprivate var bylawsFilePath: String {
      #if compiler(>=6.3)
        filePath
      #else
        _filePath
      #endif
    }
  }
#endif
