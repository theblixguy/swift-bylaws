/// A declaration or file with a known position in a source file.
public protocol Located: Sendable {
  /// The position of this value in its source file.
  var location: DeclarationLocation { get }
}
