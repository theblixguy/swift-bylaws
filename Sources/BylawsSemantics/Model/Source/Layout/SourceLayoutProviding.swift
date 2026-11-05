/// A value that describes a source arrangement.
public protocol SourceLayoutProviding: Sendable {
  /// The source arrangement described by this value.
  var layout: SourceLayout { get }
}

extension SourceLayout: SourceLayoutProviding {
  /// The captured source arrangement.
  public var layout: Self { self }
}
