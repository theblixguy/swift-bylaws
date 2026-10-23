/// A layout that cannot preserve the requested source arrangement.
public enum SourceLayoutError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// A wrapping width must be greater than zero.
  case widthMustBePositive
  /// A line contains source or layout operations that span multiple lines.
  case lineContainsNewline
  /// Multiline source cannot receive the same indentation change on every line.
  case inconsistentIndentation

  /// The layout constraint and the action that permits a replacement.
  public var description: String {
    switch self {
    case .widthMustBePositive:
      "Wrap must use a width greater than zero. Set width to a positive character count."
    case .lineContainsNewline:
      "Line must contain one physical line. Use Wrap or separate Line values for multiline source."
    case .inconsistentIndentation:
      "SourceLayout cannot change indentation on only part of multiline source. Keep its original indentation."
    }
  }
}
