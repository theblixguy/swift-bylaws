public import BylawsSemantics

/// The result of checking a package manifest against the imports its
/// targets write.
public struct PackageDependencyCheck: RuleResult, Hashable {
  /// An import of another target from the same package that is missing
  /// from the importing target's dependencies.
  public struct UndeclaredDependency: Sendable, Hashable {
    /// The target that holds the file.
    public let target: String

    /// The imported module.
    public let module: String

    /// The import that needs the dependency.
    public let importDeclaration: Import

    /// Creates an undeclared-dependency record from a check's results.
    public init(target: String, module: String, importDeclaration: Import) {
      self.target = target
      self.module = module
      self.importDeclaration = importDeclaration
    }
  }

  /// A dependency on another target from the same package with no matching
  /// import.
  public struct UnusedDependency: Sendable, Hashable {
    /// The target that declares the dependency.
    public let target: String

    /// The dependency that no file imports.
    public let module: String

    /// Creates an unused-dependency record from a check's results.
    public init(target: String, module: String) {
      self.target = target
      self.module = module
    }
  }

  /// Every import of a package target missing from the manifest's dependencies.
  public let undeclared: [UndeclaredDependency]

  /// Every declared dependency on a package target that no file imports.
  public let unused: [UnusedDependency]

  /// The targets whose source directory holds no file in the codebase.
  public let emptyTargets: [String]

  /// The number of imports the check read.
  public let checkedImportCount: Int

  /// Manifest expressions that kept the check from covering every target.
  public let unresolvedManifestValues: [PackageManifest.UnresolvedValue]

  /// Whether the check covered the complete target graph.
  public var isComplete: Bool { unresolvedManifestValues.isEmpty }

  /// The undeclared imports as violations of the package manifest.
  public var violations: Violations<Import> {
    Violations(
      rule: "declare every imported module in Package.swift",
      offenders: undeclared.map(\.importDeclaration),
      checkedCount: checkedImportCount
    )
  }
}

extension PackageDependencyCheck {
  /// Returns rule findings for the dependency result.
  ///
  /// Undeclared imports keep their source locations. Unused dependencies,
  /// empty targets and manifest fields the check cannot read use
  /// `location`.
  ///
  /// - Parameter location: The position for unused dependencies and the
  ///   warnings.
  public func findings(
    reportedAt location: DeclarationLocation
  ) -> Rule.Findings {
    let unusedOffenders = unused.map { dependency in
      Offender(
        description: "target '\(dependency.target)' declares an unused "
          + "dependency on '\(dependency.module)'",
        name: "\(dependency.target) depends on \(dependency.module)",
        location: location
      )
    }
    return Rule.Findings(
      violations: Violations(
        rule: "declare and use every package target dependency",
        offenders: violations.erased().offenders + unusedOffenders,
        checkedCount: checkedImportCount
      ),
      warnings: Rule.Warning.emptyTargets(emptyTargets, reportedAt: location)
        + unresolvedManifestValues.unreadableFieldWarnings(
          reportedAt: location
        )
    )
  }
}
