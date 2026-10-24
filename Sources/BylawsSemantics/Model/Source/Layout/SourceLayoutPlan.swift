package struct SourceLayoutPlan: Sendable, Hashable, Codable {
  package indirect enum Node: Sendable, Hashable, Codable {
    case source(Range<Int>)
    case edit(CapturedEdit)
    case sequence([Node])
    case line(Node)
    case blankLine
    case newline
    case indent(Node)
    case wrap(width: Int?, Node)
    case softBreak
    case align(Node)
  }

  package struct CapturedEdit: Sendable, Hashable, Codable {
    package let range: Range<Int>
    package let replacement: String
    package let layout: SourceLayoutPlan?

    package init(
      range: Range<Int>, replacement: String, layout: SourceLayoutPlan? = nil
    ) {
      self.range = range
      self.replacement = replacement
      self.layout = layout
    }

    package init(_ edit: SourceFix.Edit) {
      self.init(
        range: edit.source.range, replacement: edit.replacement,
        layout: edit.layout
      )
    }

    package func thaw(snapshot: SourceSnapshot) throws -> SourceFix.Edit {
      let source = try SourceSlice(snapshot: snapshot, range: range)
      try layout?.validate(source: source)
      return SourceFix.Edit(
        source: source, replacement: replacement, layout: layout
      )
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.range == rhs.range && lhs.layout == rhs.layout
        && lhs.replacement.utf8.elementsEqual(rhs.replacement.utf8)
    }

    package func hash(into hasher: inout Hasher) {
      hasher.combine(range)
      hasher.combine(layout)
      for byte in replacement.utf8 { hasher.combine(byte) }
    }
  }

  package let elements: [Range<Int>]
  package let node: Node
  package let allowsPartialList: Bool
  package let baseIndentation: String?
  package let targetRange: Range<Int>
  package let trimmed: Bool
  package let lineWidthLimit: Int?
  package let nested: [CapturedEdit]

  package init(
    elements: [Range<Int>], node: Node,
    allowsPartialList: Bool = false, baseIndentation: String? = nil,
    targetRange: Range<Int>, trimmed: Bool = false,
    lineWidthLimit: Int? = nil, nested: [CapturedEdit] = []
  ) {
    self.elements = elements
    self.node = node
    self.allowsPartialList = allowsPartialList
    self.baseIndentation = baseIndentation
    self.targetRange = targetRange
    self.trimmed = trimmed
    self.lineWidthLimit = lineWidthLimit
    self.nested = nested
  }

  package static func freeze(
    _ layout: SourceLayout, snapshot: SourceSnapshot
  ) throws -> Node {
    try Node(layout.node, snapshot: snapshot)
  }

  package func thaw(snapshot: SourceSnapshot) throws -> SourceLayout {
    try validate(source: SourceSlice(snapshot: snapshot, range: targetRange))
    return SourceLayout(node: try node.thaw(snapshot: snapshot))
  }

  package func validate(source: SourceSlice) throws {
    guard targetRange == source.range, !elements.isEmpty,
          Set(elements).count == elements.count
    else { throw SourceError.syntaxMismatch }
    if let lineWidthLimit, lineWidthLimit <= 0 {
      throw SourceLayoutError.widthMustBePositive
    }
    for range in elements { try validate(range: range, source: source) }
    try node.validate(source: source)
    for edit in nested {
      try validate(range: edit.range, source: source)
      try edit.layout?.validate(source: SourceSlice(
        snapshot: source.snapshot, range: edit.range
      ))
    }
  }

  private func validate(range: Range<Int>, source: SourceSlice) throws {
    guard range.lowerBound >= source.range.lowerBound,
          range.upperBound <= source.range.upperBound
    else { throw SourceError.rangeOutOfBounds }
    _ = try SourceSlice(snapshot: source.snapshot, range: range)
  }
}

extension SourceLayoutPlan.Node {
  fileprivate init(
    _ node: SourceLayout.Node, snapshot: SourceSnapshot
  ) throws {
    switch node {
    case let .source(provider):
      let source = try provider.source
      guard source.snapshot == snapshot else {
        throw SourceError.differentSnapshots
      }
      self = .source(source.range)
    case let .edit(edit):
      guard edit.source.snapshot == snapshot else {
        throw SourceError.differentSnapshots
      }
      self = .edit(.init(edit))
    case let .sequence(children):
      self = .sequence(try children.map { try Self($0, snapshot: snapshot) })
    case let .line(child): self = .line(try Self(child, snapshot: snapshot))
    case let .indent(child): self = .indent(try Self(child, snapshot: snapshot))
    case let .align(child): self = .align(try Self(child, snapshot: snapshot))
    case let .wrap(width, child):
      self = .wrap(width: width, try Self(child, snapshot: snapshot))
    case .blankLine: self = .blankLine
    case .newline: self = .newline
    case .softBreak: self = .softBreak
    }
  }

  fileprivate func thaw(snapshot: SourceSnapshot) throws -> SourceLayout.Node {
    switch self {
    case let .source(range):
      .source(try SourceSlice(snapshot: snapshot, range: range))
    case let .edit(edit): .edit(try edit.thaw(snapshot: snapshot))
    case let .sequence(children):
      .sequence(try children.map { try $0.thaw(snapshot: snapshot) })
    case let .line(child): .line(try child.thaw(snapshot: snapshot))
    case let .indent(child): .indent(try child.thaw(snapshot: snapshot))
    case let .align(child): .align(try child.thaw(snapshot: snapshot))
    case let .wrap(width, child):
      .wrap(width: width, try child.thaw(snapshot: snapshot))
    case .blankLine: .blankLine
    case .newline: .newline
    case .softBreak: .softBreak
    }
  }

  fileprivate func validate(source: SourceSlice) throws {
    switch self {
    case let .source(range):
      guard range.lowerBound >= source.range.lowerBound,
            range.upperBound <= source.range.upperBound
      else { throw SourceError.rangeOutOfBounds }
      _ = try SourceSlice(snapshot: source.snapshot, range: range)
    case let .edit(edit):
      guard edit.range.lowerBound >= source.range.lowerBound,
            edit.range.upperBound <= source.range.upperBound
      else { throw SourceError.rangeOutOfBounds }
      _ = try edit.thaw(snapshot: source.snapshot)
    case let .sequence(children):
      for child in children { try child.validate(source: source) }
    case let .line(child), let .indent(child), let .align(child):
      try child.validate(source: source)
    case let .wrap(width, child):
      if let width, width <= 0 { throw SourceLayoutError.widthMustBePositive }
      try child.validate(source: source)
    case .blankLine, .newline, .softBreak: break
    }
  }
}
