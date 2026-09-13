/// A value with a description that excludes its source location.
public protocol Summarised {
  /// The display text, without a file path or line number.
  var summary: String { get }
}
