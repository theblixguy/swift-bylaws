public import BylawsSemantics

/// The result of checking package imports against the stable dependencies principle.
///
/// Dependencies should point toward harder-to-change targets. The check compares
/// ``ImportGraph/Target/instability`` across each package edge.
public struct DependencyStabilityCheck: RuleResult, Hashable {
  /// An import of a target whose instability is higher than that of the
  /// target writing the import.
  public struct UnstableDependency: Sendable, Hashable {
    /// The target that writes the import.
    public let target: String

    /// The imported target.
    public let importedTarget: String

    /// The first import of ``importedTarget`` in ``target``.
    public let importDeclaration: Import

    /// The instability of ``target``.
    public let instability: Double

    /// The instability of ``importedTarget``, which is the higher value.
    public let importedInstability: Double

    /// Creates a record of one unstable import.
    public init(
      target: String,
      importedTarget: String,
      importDeclaration: Import,
      instability: Double,
      importedInstability: Double
    ) {
      self.target = target
      self.importedTarget = importedTarget
      self.importDeclaration = importDeclaration
      self.instability = instability
      self.importedInstability = importedInstability
    }
  }

  /// Every edge that points at a target with a higher instability, in
  /// declaration order.
  public let unstable: [UnstableDependency]

  /// The targets whose source directory holds no file in the codebase.
  public let emptyTargets: [String]

  /// The number of edges the check compared.
  public let checkedEdgeCount: Int

  /// Manifest expressions that kept the check from covering every target.
  public let unresolvedManifestValues: [PackageManifest.UnresolvedValue]

  /// Whether the check covered the complete target graph.
  public var isComplete: Bool { unresolvedManifestValues.isEmpty }

  /// The unstable imports as violations of the stable dependencies principle.
  public var violations: Violations<Import> {
    Violations(
      rule: "depend on a target that is harder to change",
      offenders: unstable.map(\.importDeclaration),
      checkedCount: checkedEdgeCount
    )
  }
}

extension DependencyStabilityCheck {
  /// Returns rule findings for the stability result.
  ///
  /// Each unstable edge points at the import that carries it. Empty targets
  /// and manifest fields the check cannot read become warnings at
  /// `location`.
  ///
  /// - Parameter location: The position for the warnings.
  public func findings(
    reportedAt location: DeclarationLocation
  ) -> Rule.Findings {
    Rule.Findings(
      violations: Violations(
        rule: violations.rule,
        offenders: unstable.map { edge in
          Offender(
            description: """
            \(edge.target) (\(formattedInstability(edge.instability))) \
            imports the freer \(edge.importedTarget) \
            (\(formattedInstability(edge.importedInstability)))
            """,
            name: "\(edge.target) depends on \(edge.importedTarget)",
            location: edge.importDeclaration.location
          )
        },
        checkedCount: checkedEdgeCount
      ),
      warnings: Rule.Warning.emptyTargets(emptyTargets, reportedAt: location)
        + unresolvedManifestValues.unreadableFieldWarnings(
          reportedAt: location
        )
    )
  }
}

private func formattedInstability(_ value: Double) -> String {
  let hundredths = Int((value * 100).rounded())
  let fraction = hundredths % 100
  return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
}
