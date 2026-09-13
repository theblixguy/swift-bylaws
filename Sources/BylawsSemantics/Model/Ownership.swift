/// The reference-ownership modifier on a property.
public enum Ownership: String, CaseIterable, Sendable, Hashable, Codable {
  /// A weak reference.
  case weak

  /// An unowned reference.
  case unowned
}
