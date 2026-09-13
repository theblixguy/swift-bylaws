/// The protocol the index tests query for conformers.
public protocol PortableSubject {}

/// A protocol that inherits ``PortableSubject``. Its conformers are indirect
/// conformers of ``PortableSubject``.
public protocol NamedPortableSubject: PortableSubject {
  /// The name the subject reports.
  var subjectName: String { get }
}

/// An indirect conformer of ``PortableSubject``, through
/// ``NamedPortableSubject``.
public struct SupportSubject: NamedPortableSubject {
  /// The name the subject reports.
  public let subjectName = "support"

  /// Creates a subject.
  public init() {}
}
