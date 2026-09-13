/// How a rule's violations count against a run.
///
/// An enforced rule fails the run. Advisory violations remain visible without
/// failing. Use advisory enforcement to review a rule before enforcing it.
public enum Enforcement: String, CaseIterable, Sendable, Hashable, Codable {
  /// Violations remain visible without failing the run.
  case advisory

  /// Violations fail the run.
  case enforced
}
