package struct SourceLayoutPlan: Sendable, Hashable, Codable {
  package indirect enum Node: Sendable, Hashable, Codable {
    case source(Range<Int>)
    case edit(CapturedEdit)
    case sequence([Node])
    case line(Node)
    case lines(Node)
    case boundedLines(Node)
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

    package func resolve(snapshot: SourceSnapshot) throws -> SourceFix.Edit {
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

  package struct Layout: Sendable, Hashable, Codable {
    package let node: Node
    package let allowsPartialList: Bool
    package let baseIndentation: String?
    package let trimmed: Bool
    package let condition: SourceLayoutCondition?
    package let nested: [NestedEdit]

    package init(
      node: Node,
      allowsPartialList: Bool = false,
      baseIndentation: String? = nil,
      trimmed: Bool = false,
      condition: SourceLayoutCondition? = nil,
      nested: [NestedEdit] = []
    ) {
      self.node = node
      self.allowsPartialList = allowsPartialList
      self.baseIndentation = baseIndentation
      self.trimmed = trimmed
      self.condition = condition
      self.nested = nested
    }
  }

  package enum Mode: Sendable, Hashable, Codable {
    case layout(Layout)
  }

  package let elements: [Range<Int>]
  package let targetRange: Range<Int>
  package let mode: Mode

  package var formatting: Layout? {
    switch mode {
    case let .layout(layout): layout
    }
  }

  package init(elements: [Range<Int>], targetRange: Range<Int>, mode: Mode) {
    self.elements = elements
    self.targetRange = targetRange
    self.mode = mode
  }

  package init(
    elements: [Range<Int>], node: Node,
    allowsPartialList: Bool = false, baseIndentation: String? = nil,
    targetRange: Range<Int>, trimmed: Bool = false,
    condition: SourceLayoutCondition? = nil, nested: [NestedEdit] = []
  ) {
    self.init(
      elements: elements,
      targetRange: targetRange,
      mode: .layout(Layout(
        node: node, allowsPartialList: allowsPartialList,
        baseIndentation: baseIndentation, trimmed: trimmed,
        condition: condition, nested: nested
      ))
    )
  }

  package static func capture(
    _ layout: SourceLayout, snapshot: SourceSnapshot
  ) throws -> Node {
    try Node(layout.node, snapshot: snapshot)
  }

  package func resolve(snapshot: SourceSnapshot) throws -> SourceLayout {
    try validate(source: SourceSlice(snapshot: snapshot, range: targetRange))
    guard let formatting else { throw SourceError.syntaxMismatch }
    return SourceLayout(node: try formatting.node.resolve(snapshot: snapshot))
  }

  package func validate(source: SourceSlice) throws {
    guard targetRange == source.range,
          Set(elements).count == elements.count
    else { throw SourceError.syntaxMismatch }
    switch mode {
    case .layout:
      guard !elements.isEmpty else { throw SourceError.syntaxMismatch }
    }
    for range in elements { try validate(range: range, source: source) }
    if let formatting {
      try formatting.node.validate(source: source)
      for edit in formatting.nested {
        try validate(range: edit.range, source: source)
        try edit.layout?.validate(source: SourceSlice(
          snapshot: source.snapshot, range: edit.range
        ))
      }
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
    case let .failure(error): throw error
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
    case let .lines(child): self = .lines(try Self(child, snapshot: snapshot))
    case let .boundedLines(child): self = .boundedLines(try Self(
        child,
        snapshot: snapshot
      ))
    case let .indent(child): self = .indent(try Self(child, snapshot: snapshot))
    case let .align(child): self = .align(try Self(child, snapshot: snapshot))
    case let .wrap(width, child):
      self = .wrap(width: width, try Self(child, snapshot: snapshot))
    case .blankLine: self = .blankLine
    case .newline: self = .newline
    case .softBreak: self = .softBreak
    }
  }

  fileprivate func resolve(snapshot: SourceSnapshot) throws -> SourceLayout
    .Node
  {
    switch self {
    case let .source(range):
      .source(try SourceSlice(snapshot: snapshot, range: range))
    case let .edit(edit): .edit(try edit.resolve(snapshot: snapshot))
    case let .sequence(children):
      .sequence(try children.map { try $0.resolve(snapshot: snapshot) })
    case let .line(child): .line(try child.resolve(snapshot: snapshot))
    case let .lines(child): .lines(try child.resolve(snapshot: snapshot))
    case let .boundedLines(child): .boundedLines(try child
        .resolve(snapshot: snapshot))
    case let .indent(child): .indent(try child.resolve(snapshot: snapshot))
    case let .align(child): .align(try child.resolve(snapshot: snapshot))
    case let .wrap(width, child):
      .wrap(width: width, try child.resolve(snapshot: snapshot))
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
      _ = try edit.resolve(snapshot: source.snapshot)
    case let .sequence(children):
      for child in children { try child.validate(source: source) }
    case let .line(child), let .lines(child), let .boundedLines(child),
         let .indent(child),
         let .align(child):
      try child.validate(source: source)
    case let .wrap(width, child):
      if let width, width <= 0 { throw SourceLayoutError.widthMustBePositive }
      try child.validate(source: source)
    case .blankLine, .newline, .softBreak: break
    }
  }
}
