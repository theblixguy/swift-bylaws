/// A source list that retains its location when it has no elements.
public struct SourceList<Element: SourceProviding>: RandomAccessCollection,
  SourceProviding
{
  private let elements: [Element]
  let context: SourceListContext

  init(
    _ elements: [Element],
    owner: SourceSlice,
    kind: SourceListContext.Kind
  ) {
    self.elements = elements
    context = SourceListContext(owner: owner, kind: kind)
  }

  /// The first element's index.
  public var startIndex: Int { elements.startIndex }

  /// The position after the last element.
  public var endIndex: Int { elements.endIndex }

  /// The element at the given index.
  public subscript(position: Int) -> Element { elements[position] }

  /// The list's contents, including the gaps between its elements.
  public var source: SourceSlice {
    get throws { try context.resolve().source }
  }

  /// Returns a correction that inserts one element at the given position.
  ///
  /// The text must contain one element of this list's kind. Bylaws adds the
  /// list's separators and retains its existing indentation.
  /// If a layout also changes the list, the new element uses the adjacent
  /// element's layout.
  public func inserting(
    _ text: String, at position: SourceListPosition = .end
  ) throws -> SourceCorrection {
    let list = try context.resolve()
    let correction = try SourceListEditing.insert(
      text,
      into: list,
      at: position
    )
    return try SourceListMutationPlan.capture(
      correction, list: list, operation: .insert(text, at: position)
    )
  }

  /// Returns a correction that removes this element and its list separator.
  public func removing(_ element: Element) throws -> SourceCorrection {
    let source = try element.source
    guard source.snapshot == context.owner.snapshot else {
      throw SourceError.differentSnapshots
    }
    let list = try context.resolve()
    let correction = try SourceListEditing.remove(source, from: list)
    return try SourceListMutationPlan.capture(
      correction, list: list, operation: .remove(source.range)
    )
  }

  package func sourceSlices() throws -> SourceList<SourceSlice> {
    try SourceList<SourceSlice>(
      map { try $0.source },
      owner: context.owner,
      kind: context.kind
    )
  }
}

/// A position at which to insert an element in a source list.
public enum SourceListPosition: Sendable, Hashable, Codable {
  /// Before the first element in the final list.
  case start
  /// After the last element in the final list.
  case end
  /// Before the captured element at this index, even if a layout moves it.
  /// The list's `endIndex` inserts after the final element.
  case index(Int)

  func offset(count: Int) throws -> Int {
    let index = switch self {
    case .start: 0
    case .end: count
    case let .index(index): index
    }
    guard (0...count).contains(index)
    else { throw SourceError.rangeOutOfBounds }
    return index
  }
}
