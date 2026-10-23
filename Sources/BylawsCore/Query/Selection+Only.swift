extension Selection {
  /// Returns the single selected element.
  ///
  /// - Throws: ``SelectionCountError`` when the selection is empty or contains
  ///   more than one element.
  public func only() throws(SelectionCountError) -> Element {
    guard count == 1, let element = first else {
      throw SelectionCountError(count: count, query: queryDescription)
    }
    return element
  }
}

/// An error from a selection with zero or multiple elements.
public struct SelectionCountError: Error, Sendable, CustomStringConvertible {
  /// The number of selected elements.
  public let count: Int

  /// The query that produced the selection.
  public let query: String

  /// A description of the selection count and query.
  public var description: String {
    "the selection must contain one element; '\(query)' returned \(count)"
  }
}
