/// A proposed arrangement of captured source elements.
public struct SourceLayout: Sendable {
  package indirect enum Node: Sendable {
    case source(any SourceProviding)
    case edit(SourceFix.Edit)
    case sequence([Node])
    case line(Node)
    case blankLine
    case newline
    case indent(Node)
    case wrap(width: Int?, Node)
    case softBreak
    case align(Node)
  }

  package let node: Node

  /// Creates a layout from captured source and layout operations.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self = try content()
  }

  package init(node: Node) {
    self.node = node
  }

  package var sources: [any SourceProviding] {
    node.sources
  }

  package var edits: [SourceFix.Edit] {
    node.edits
  }
}

extension SourceLayout.Node {
  private var children: [Self] {
    switch self {
    case let .sequence(children): children
    case let .line(child), let .indent(child), let .wrap(_, child),
         let .align(child): [child]
    case .source, .edit, .blankLine, .newline, .softBreak: []
    }
  }

  fileprivate var sources: [any SourceProviding] {
    switch self {
    case let .source(source): [source]
    case let .edit(edit): [edit.source]
    default: children.flatMap(\.sources)
    }
  }

  fileprivate var edits: [SourceFix.Edit] {
    switch self {
    case let .edit(edit): [edit]
    default: children.flatMap(\.edits)
    }
  }
}

extension SourceSlice: SourceProviding {
  /// The captured source slice.
  public var source: Self { self }
}
