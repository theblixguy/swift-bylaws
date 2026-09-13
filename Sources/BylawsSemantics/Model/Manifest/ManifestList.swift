/// Values read from a collection in a `Package.swift` file.
///
/// A manifest can build a collection with Swift code. Use ``values`` to check
/// that an item is absent.
public struct ManifestList<Element: Sendable & Hashable & Codable>: Sendable,
  Hashable, Codable
{
  /// Values that occur without an unknown condition.
  public let knownValues: [Element]

  /// Values under a condition that Bylaws could not evaluate.
  public let conditionalValues: [Element]

  /// Expressions that Bylaws could not evaluate.
  public let unresolvedValues: [PackageManifest.UnresolvedValue]

  /// Whether Bylaws read all values in the collection.
  public var isComplete: Bool {
    conditionalValues.isEmpty && unresolvedValues.isEmpty
  }

  /// Resolved values that can occur in the collection.
  public var possibleValues: [Element] { knownValues + conditionalValues }

  /// All values, or `nil` when the list is incomplete.
  ///
  /// An element can contain its own unresolved fields. Check the element's
  /// completeness when a rule depends on those fields.
  public var values: [Element]? {
    isComplete ? knownValues : nil
  }

  /// Creates a manifest collection.
  public init(
    knownValues: [Element] = [],
    conditionalValues: [Element] = [],
    unresolvedValues: [PackageManifest.UnresolvedValue] = []
  ) {
    self.knownValues = knownValues
    self.conditionalValues = conditionalValues
    self.unresolvedValues = unresolvedValues
  }
}
