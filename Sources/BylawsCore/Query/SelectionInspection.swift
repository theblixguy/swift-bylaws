public import BylawsSemantics

/// The elements kept and removed by one Bylaws selection step.
public struct SelectionInspection: Sendable, Hashable, Codable {
  /// The name, description and source location of a selected file or declaration.
  public struct Element: Sendable, Hashable, Codable {
    /// The declaration or file name, if the selected element has one.
    public let name: String?
    /// A summary for display when the name alone does not identify the element.
    public let description: String
    /// The element's position in its source file.
    public let location: DeclarationLocation

    package init(
      name: String?,
      description: String,
      location: DeclarationLocation
    ) {
      self.name = name
      self.description = description
      self.location = location
    }

    package init?(_ value: some Sendable) {
      guard let located = value as? any Located else { return nil }
      self.init(
        name: (value as? any Named)?.name,
        description: (value as? any Summarised)?
          .summary ?? String(describing: value),
        location: located.location
      )
    }
  }

  /// A description of the query and filters up to and including this step.
  public let queryDescription: String
  /// The elements kept by this step, in selection order.
  public let selected: [Element]
  /// The elements removed from the previous selection, or none for a new query.
  public let excluded: [Element]

  package init(
    queryDescription: String,
    selected: [Element],
    excluded: [Element]
  ) {
    self.queryDescription = queryDescription
    self.selected = selected
    self.excluded = excluded
  }
}
