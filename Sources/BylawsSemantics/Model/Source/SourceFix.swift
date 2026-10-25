/// A proposed correction whose edits apply together.
public struct SourceFix: Sendable, Hashable, Codable {
  /// The description of the correction, when supplied.
  public let title: String?

  /// The replacements against the original source snapshots.
  public let edits: [Edit]

  package let layoutCandidates: [Edit]

  /// Creates a correction from its replacements.
  public init(_ title: String? = nil, edits: [Edit]) {
    self.init(title, edits: edits, layoutCandidates: [])
  }

  package init(
    _ title: String? = nil, edits: [Edit], layoutCandidates: [Edit]
  ) {
    self.title = title
    self.edits = edits
    self.layoutCandidates = layoutCandidates
  }

  package init(
    _ title: String? = nil, proposedEdits: [Edit],
    layoutCandidates: [Edit] = []
  ) {
    var edits: [Edit] = []
    var candidates = layoutCandidates
    for edit in proposedEdits {
      if edit.source.text.utf8.elementsEqual(edit.replacement.utf8) {
        if edit.layout != nil { candidates.append(edit) }
      } else {
        edits.append(edit)
      }
    }
    self.init(title, edits: edits, layoutCandidates: candidates)
  }

  private enum CodingKeys: String, CodingKey {
    case title, edits, layoutCandidates
  }

  /// Decodes a correction.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let candidates = try values.decodeIfPresent(
      [Edit].self, forKey: .layoutCandidates
    ) ?? []
    for candidate in candidates { try candidate.validateLayoutCandidate() }
    self.init(
      try values.decodeIfPresent(String.self, forKey: .title),
      edits: try values.decode([Edit].self, forKey: .edits),
      layoutCandidates: candidates
    )
  }

  /// Encodes a correction.
  public func encode(to encoder: any Encoder) throws {
    for candidate in layoutCandidates { try candidate.validateLayoutCandidate()
    }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(title, forKey: .title)
    try values.encode(edits, forKey: .edits)
    if !layoutCandidates.isEmpty {
      try values.encode(layoutCandidates, forKey: .layoutCandidates)
    }
  }

  /// One replacement against an original source snapshot.
  public struct Edit: Sendable, Hashable, Codable {
    /// The original source to replace.
    public let source: SourceSlice

    /// The text to write in place of the original source.
    public let replacement: String

    package let layout: SourceLayoutPlan?

    package init(
      source: SourceSlice, replacement: String, layout: SourceLayoutPlan? = nil
    ) {
      self.source = source
      self.replacement = replacement
      self.layout = layout
    }

    package func validateLayoutCandidate() throws {
      guard layout != nil,
            source.text.utf8.elementsEqual(replacement.utf8)
      else { throw SourceLayoutComposition.Failure.changedCandidate }
      try SourceLayoutComposition.validate(self)
    }

    /// Compares the source spans, layout policies and exact replacement bytes.
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.source == rhs.source && lhs.layout == rhs.layout
        && lhs.replacement.utf8.elementsEqual(rhs.replacement.utf8)
    }

    /// Hashes the source span, layout policy and exact replacement bytes.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(source)
      hasher.combine(layout)
      for byte in replacement.utf8 { hasher.combine(byte) }
    }

    private enum CodingKeys: String, CodingKey {
      case source, replacement, layout
    }

    /// Decodes a replacement and checks its captured layout ranges.
    public init(from decoder: any Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      let source = try values.decode(SourceSlice.self, forKey: .source)
      let layout = try values.decodeIfPresent(
        SourceLayoutPlan.self,
        forKey: .layout
      )
      self.init(
        source: source,
        replacement: try values.decode(String.self, forKey: .replacement),
        layout: layout
      )
      try SourceLayoutComposition.validate(self)
    }

    /// Encodes the replacement and its captured layout.
    public func encode(to encoder: any Encoder) throws {
      try SourceLayoutComposition.validate(self)
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(source, forKey: .source)
      try values.encode(replacement, forKey: .replacement)
      try values.encodeIfPresent(layout, forKey: .layout)
    }
  }
}
