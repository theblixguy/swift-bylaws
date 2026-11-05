/// A proposed arrangement of captured source elements.
public struct SourceLayout: Sendable {
  package indirect enum Node: Sendable {
    case source(any SourceProviding)
    case edit(SourceFix.Edit)
    case sequence([Node])
    case line(Node)
    case lines(Node)
    case joined(Node)
    case boundedLines(Node)
    case blankLine
    case newline
    case indent(Node)
    case wrap(width: Int?, Node)
    case softBreak
    case align(Node)
    case failure(SourceCorrectionError)
  }

  package let node: Node

  /// Creates a layout from captured source and layout operations.
  public init(@SourceLayoutBuilder _ content: () throws
    -> SourceLayout) rethrows
  {
    self = try content()
  }

  /// Creates a layout containing one captured source element.
  public init(_ source: some SourceProviding) {
    node = .source(source)
  }

  /// Creates a layout containing captured source elements in collection order.
  public init<S: Sequence>(_ sources: S) where S.Element: SourceProviding {
    node = .sequence(sources.map { .source($0) })
  }

  /// Creates a layout containing the elements of a captured source list.
  public init(_ sources: SourceList<some SourceProviding>) {
    node = .sequence(sources.map { .source($0) })
  }

  /// Creates a layout that includes an edit within its containing source element.
  public init(_ edit: SourceFix.Edit) {
    node = .edit(edit)
  }

  /// Combines stored layouts in their supplied order.
  public init(_ layouts: [Self]) {
    node = .sequence(layouts.map(\.node))
  }

  /// Creates a layout from a stored layout component.
  public init(_ component: some SourceLayoutProviding) {
    self = component.layout
  }

  /// Includes a correction's edits and retains an unavailable or unknown result.
  public init(_ operation: some SourceCorrectionProviding) {
    do {
      let fix = try operation.correction.preparedFix()
      node = .sequence(((fix?.edits ?? []) + (fix?.layoutCandidates ?? []))
        .map { .edit($0) })
    } catch {
      node = .failure(error)
    }
  }

  /// A required line break between elements or at a list boundary.
  public static var newline: Self { Self(node: .newline) }

  /// An empty line between nonempty output.
  public static var blankLine: Self { Self(node: .blankLine) }

  /// An optional line break, rendered as a space when the content fits.
  public static var softBreak: Self { Self(node: .softBreak) }

  package init(node: Node) {
    self.node = node
  }

  package var isEmpty: Bool { node.isEmpty }

  package var correctionError: SourceCorrectionError? { node.correctionError }

  package var sources: [any SourceProviding] {
    get throws {
      if let correctionError { throw correctionError }
      return try node.sources
    }
  }

  package var edits: [SourceFix.Edit] {
    get throws {
      if let correctionError { throw correctionError }
      return try node.edits
    }
  }
}

extension SourceLayout.Node {
  fileprivate var isEmpty: Bool {
    switch self {
    case let .sequence(children): children.allSatisfy(\.isEmpty)
    case let .line(child), let .lines(child), let .joined(child),
         let .boundedLines(child),
         let .indent(child),
         let .wrap(_, child), let .align(child): child.isEmpty
    case .source, .edit, .blankLine, .newline, .softBreak, .failure: false
    }
  }

  fileprivate var correctionError: SourceCorrectionError? {
    switch self {
    case let .failure(error): return error
    case let .sequence(children):
      var unavailable: SourceCorrectionError?
      for child in children {
        guard let error = child.correctionError else { continue }
        if case .undetermined = error { return error }
        unavailable = unavailable ?? error
      }
      return unavailable
    case let .line(child), let .lines(child), let .joined(child),
         let .boundedLines(child),
         let .indent(child),
         let .wrap(_, child), let .align(child):
      return child.correctionError
    case .source, .edit, .blankLine, .newline, .softBreak: return nil
    }
  }

  private var children: [Self] {
    switch self {
    case let .sequence(children): children
    case let .line(child), let .lines(child), let .joined(child),
         let .boundedLines(child),
         let .indent(child),
         let .wrap(_, child), let .align(child): [child]
    case .source, .edit, .blankLine, .newline, .softBreak, .failure: []
    }
  }

  fileprivate var sources: [any SourceProviding] {
    get throws {
      switch self {
      case let .source(source): [source]
      case let .edit(edit): [edit.source]
      case let .failure(error): throw error
      default: try children.flatMap { try $0.sources }
      }
    }
  }

  fileprivate var edits: [SourceFix.Edit] {
    get throws {
      switch self {
      case let .edit(edit): [edit]
      case let .failure(error): throw error
      default: try children.flatMap { try $0.edits }
      }
    }
  }
}

extension SourceSlice: SourceProviding {
  /// The captured source slice.
  public var source: Self { self }
}
