public import BylawsCore
import BylawsPaths

package enum RuleFileStatus: Sendable {
  case found
  case missing
}

/// The rules and diagnostics loaded from `Bylaws.swift` files.
///
/// Loading returns every accepted rule and a source-located ``Diagnostic`` for
/// each rejected construct. The CLI exits on an error diagnostic.
/// ``BylawsCore/Rule/discovered(above:)`` throws a ``RuleDiscoveryError``.
public struct RuleProgram: Sendable {
  /// One loaded rule and its optional project scope.
  public struct LoadedRule: Sendable {
    /// The loaded rule.
    public let rule: Rule

    /// The rule's project scope, or `nil` when the rule is unscoped.
    public let scope: RuleScope?

    /// Creates a loaded rule with a project scope.
    ///
    /// - Precondition: The scope names `rule`.
    public init(rule: Rule, scope: RuleScope) {
      precondition(
        rule.id == scope.id,
        "a loaded rule and its scope must carry the same ID"
      )
      self.rule = rule
      self.scope = scope
    }

    /// Creates a loaded rule without a project scope.
    public init(unscoped rule: Rule) {
      self.rule = rule
      scope = nil
    }
  }

  /// The rules and their optional scopes, in declaration order.
  public let loadedRules: [LoadedRule]

  /// The rules, in declaration order, root file first.
  ///
  /// Complexity: O(*n*), where *n* is the number of loaded rules.
  public var rules: [Rule] {
    loadedRules.map(\.rule)
  }

  /// The diagnostics the interpreter reported while loading, in file order.
  public let diagnostics: [Diagnostic]

  package let ruleFileStatus: RuleFileStatus
  package let pathsThatDidNotParse: [String]

  /// The directory scopes, in loaded-rule order.
  ///
  /// Only scoped rules appear in this view. ``loadedRules`` retains each
  /// scope's association with its rule.
  ///
  /// Complexity: O(*n*), where *n* is the number of loaded rules.
  public var scopes: [RuleScope] {
    loadedRules.compactMap(\.scope)
  }

  /// Creates a program from loaded rules and diagnostics.
  public init(loadedRules: [LoadedRule], diagnostics: [Diagnostic]) {
    self.init(
      loadedRules: loadedRules,
      diagnostics: diagnostics,
      ruleFileStatus: .found
    )
  }

  package init(
    loadedRules: [LoadedRule],
    diagnostics: [Diagnostic],
    ruleFileStatus: RuleFileStatus,
    pathsThatDidNotParse: [String] = []
  ) {
    self.loadedRules = loadedRules
    self.diagnostics = diagnostics
    self.ruleFileStatus = ruleFileStatus
    self.pathsThatDidNotParse = pathsThatDidNotParse
  }

  /// The diagnostics with the ``Diagnostic/Severity/error`` severity.
  public var errors: [Diagnostic] {
    diagnostics.filter { $0.severity == .error }
  }

  /// Returns the rules that apply to `relativePath`.
  ///
  /// The scopes filter by directory alone, and a rule's own globs narrow
  /// further. A program needs a scope before a rule can apply to a path.
  public func rules(applyingTo relativePath: String) -> [Rule] {
    loadedRules(applyingTo: relativePath).map(\.rule)
  }

  /// Returns the loaded rules that apply to `relativePath`, each with its
  /// scope.
  ///
  /// The scopes filter by directory alone, and a rule's own globs narrow
  /// further. A program needs a scope before a rule can apply to a path.
  public func loadedRules(applyingTo relativePath: String) -> [LoadedRule] {
    loadedRules.filter { $0.scope?.applies(to: relativePath) == true }
  }
}

/// The project directories where a rule applies.
///
/// A scope begins at the declaring file's directory and omits module subtrees
/// that override the rule.
public struct RuleScope: Sendable {
  /// The rule the scope belongs to.
  public let id: Rule.ID

  /// The declaring file's directory relative to the root, empty for the
  /// root file.
  public let directory: String

  /// The module subtrees an `Override` removed from the scope.
  public let excludedSubtrees: [String]

  /// The justification an `Override` declared, or `nil` when the rule is not
  /// an override.
  public let overrideReason: String?

  /// Creates a scope from its parts.
  public init(
    id: Rule.ID,
    directory: String,
    excludedSubtrees: [String],
    overrideReason: String? = nil
  ) {
    self.id = id
    self.directory = directory
    self.excludedSubtrees = excludedSubtrees
    self.overrideReason = overrideReason
  }

  /// Returns whether `relativePath` is inside the scope.
  public func applies(to relativePath: String) -> Bool {
    let path = LexicalFilePath(relativePath)
    if !directory.isEmpty,
       !LexicalFilePath(directory).contains(path)
    {
      return false
    }
    return !excludedSubtrees.contains { subtree in
      LexicalFilePath(subtree).contains(path)
    }
  }
}
