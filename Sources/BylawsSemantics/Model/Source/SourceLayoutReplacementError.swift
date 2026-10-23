/// A source list that cannot be rearranged without losing source ownership.
public enum SourceLayoutReplacementError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// The input collection has no source elements.
  case emptyCollection
  /// The elements come from different source snapshots.
  case differentSnapshots
  /// An element does not represent a supported syntax-list item.
  case unsupportedElement
  /// The elements span several lists or omit part of a supported source list.
  case noncontiguousElements
  /// The output contains an input element more than once.
  case repeatedElement
  /// The output omits an input element.
  case missingElement
  /// The output contains an element outside the input collection.
  case foreignElement
  /// A comment or directive has no unambiguous owner in the replacement.
  case ambiguousTrivia
  /// A conditional-compilation declaration separates the elements.
  case conditionalCompilation

  /// The source constraint and the action that permits a replacement.
  public var description: String {
    switch self {
    case .emptyCollection:
      "SourceLayout must contain at least one input element. Select a non-empty source list."
    case .differentSnapshots:
      "SourceLayout must use one source snapshot. Select elements from the same parsed file."
    case .unsupportedElement:
      "SourceLayout must contain complete supported list elements. Select attributes, declarations, statements or literal elements."
    case .noncontiguousElements:
      "SourceLayout must contain consecutive elements from one list. Select a complete list or a consecutive run of declarations or statements."
    case .repeatedElement:
      "SourceLayout must emit each input element once. Remove repeated elements from the layout."
    case .missingElement:
      "SourceLayout must emit every input element. Include the missing elements in the layout."
    case .foreignElement:
      "SourceLayout must emit elements from its input collection. Select the complete input list before building the layout."
    case .ambiguousTrivia:
      "SourceLayout cannot assign a comment or directive to one element. Select a region with clear comment ownership."
    case .conditionalCompilation:
      "SourceLayout cannot cross conditional-compilation boundaries. Format each branch separately."
    }
  }
}
