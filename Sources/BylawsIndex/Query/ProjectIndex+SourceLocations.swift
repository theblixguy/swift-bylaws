public import BylawsIndexStore
public import BylawsSemantics

extension ProjectIndex {
  /// Returns every compiler occurrence at the given source location.
  ///
  /// Use the source from the indexed build and the position of the identifier
  /// you want to check, such as `send` in `client.send()`.
  ///
  /// A position can have several occurrences, including implicit ones. You
  /// can filter the results by `symbol.usr` and `roles`. The array is empty
  /// when the index has no occurrence at that position.
  ///
  /// - Complexity: O(log n + k), where n is the number of indexed occurrences
  ///   and k is the number at this position.
  public func occurrences(at location: DeclarationLocation)
    -> [IndexReference]
  {
    occurrences(
      in: location.filePath,
      line: location.line,
      column: location.column
    )
  }
}
