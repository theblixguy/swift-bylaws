/// A declaration or file that has a name.
public protocol Named: Sendable {
  /// The name, as written in source.
  var name: String { get }
}
