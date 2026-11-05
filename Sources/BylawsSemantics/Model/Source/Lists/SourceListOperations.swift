/// Inserts one element into a captured source list.
public struct Insert: SourceCorrectionProviding {
  /// The correction prepared for the selected list.
  public let correction: SourceCorrection

  /// Creates an insertion at the given list position.
  public init(
    _ text: String, into list: SourceList<some SourceProviding>,
    at position: SourceListPosition = .end
  ) throws {
    correction = try list.inserting(text, at: position)
  }
}

/// Removes a captured list element and its separator.
public struct Remove: SourceCorrectionProviding {
  /// The correction prepared for the selected element.
  public let correction: SourceCorrection

  /// Creates a removal for a complete argument, attribute, modifier, member or statement.
  public init(_ element: some SourceProviding) throws {
    correction = try element.removal()
  }
}

extension SourceProviding {
  /// Returns a correction that removes this list element and its separator.
  public func removal() throws -> SourceCorrection {
    try SourceListEditing.remove(source)
  }
}
