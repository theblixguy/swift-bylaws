/// A read-only view of one type's members in source order.
public struct MemberCollection<Element: Sendable>: RandomAccessCollection,
  Sendable
{
  @usableFromInline
  let elements: [Element]

  @usableFromInline
  let indices: [Int]

  package init(elements: [Element], indices: [Int]) {
    self.elements = elements
    self.indices = indices
  }

  /// The position of the first member.
  @inlinable
  public var startIndex: Int { indices.startIndex }

  /// The position after the last member.
  @inlinable
  public var endIndex: Int { indices.endIndex }

  /// Returns the member at `position`.
  ///
  /// - Complexity: O(1).
  @inlinable
  public subscript(position: Int) -> Element {
    elements[indices[position]]
  }
}
