public import BylawsCore

extension Rule {
  /// Returns the rules the project's `Bylaws.swift` files declare.
  ///
  /// Root discovery follows `Codebase(root: .automatic())` and starts above
  /// `filePath`. In a test target, `Rule.discovered()` lints the containing
  /// project:
  ///
  /// ```swift
  /// @Test(.annotatesViolations, arguments: try await Rule.discovered())
  /// func holds(_ rule: Rule) async throws {
  ///   try await #expect(rule.violations().isEmpty)
  /// }
  /// ```
  ///
  /// This form throws. ``RuleProgram/discovered(atRoot:)`` runs the same
  /// discovery from a known root and reports failures as diagnostics
  /// instead.
  ///
  /// - Throws: ``RuleDiscoveryError/unresolvedRoot(_:)`` when no project root
  ///   exists above `filePath`, or ``RuleDiscoveryError/invalidRules(_:)``
  ///   containing every diagnostic from a failed rules load.
  ///
  /// ## See Also
  ///
  /// - ``RuleProgram/discovered(atRoot:)``
  public static func discovered(
    above filePath: String = #filePath
  ) async throws(RuleDiscoveryError) -> [Rule] {
    let root: String
    do {
      root = try Codebase.automaticRoot(above: filePath)
    } catch {
      throw .unresolvedRoot(error)
    }
    let program = await RuleProgram.discovered(atRoot: root)
    guard program.errors.isEmpty else {
      throw .invalidRules(BylawsFileError(diagnostics: program.diagnostics))
    }
    return program.rules
  }
}
