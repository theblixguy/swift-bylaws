public import PortableRuleSupport

/// A direct conformer of ``PortableSubject``, declared in a module other
/// than the one that declares the protocol.
public struct RuleSubject: PortableSubject {
  /// Creates a subject.
  public init() {}
}
