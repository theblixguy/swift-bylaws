/// A correction that arranges a captured source list.
///
/// Source and layout validation errors throw. An unavailable or undetermined
/// correction included in the layout is retained in ``correction``.
public struct Layout<Element: SourceProviding>: SourceCorrectionProviding {
  /// The checked arrangement and its proposed edits.
  public let correction: SourceCorrection

  package init(correction: SourceCorrection) {
    self.correction = correction
  }

  /// Arranges a source list with explicit elements or grouping and spacing policies.
  ///
  /// Empty input or an empty layout produces no correction. A condition checks
  /// each region affected by a policy after any containing layout moves it.
  public init(
    _ elements: some Collection<Element>,
    when condition: SourceLayoutCondition? = nil,
    @LayoutBuilder<Element> _ content: () throws -> LayoutContent<Element>
  ) throws {
    try self.init(elements, layout: content(), when: condition)
  }

  /// Arranges a source list with a stored layout description.
  public init(
    _ elements: some Collection<Element>,
    layout: LayoutContent<Element>,
    when condition: SourceLayoutCondition? = nil
  ) throws {
    do {
      let components = layout.components
      if components.allSatisfy({ component in
        if case let .layout(layout) = component { layout.isEmpty }
        else { false }
      }) {
        correction = .notApplicable
        return
      }
      let hasPolicies = components.contains {
        switch $0 {
        case .group, .blankLine, .newline: true
        case .layout, .separator, .sequence: false
        }
      }
      let fix: SourceFix
      if hasPolicies {
        let embedded =
          SourceLayout(node: .sequence(components.compactMap { component in
            if case let .layout(layout) = component { layout.node } else { nil }
          }))
        if let error = embedded.correctionError { throw error }
        let directives = try components.map { component
          -> SourceListLayout<Element>.Directive in
          switch component {
          case let .group(group): return .group(group)
          case let .separator(whitespace):
            try Self.validate(whitespace)
            return .separator(whitespace)
          case let .blankLine(line): return .conditional(
              line.separator,
              .blankLine
            )
          case let .newline(line): return .conditional(line.separator, .newline)
          case .layout, .sequence: throw SourceListLayoutError.mixedContent
          }
        }
        fix = try SourceListLayoutReplacement.make(
          elements: Array(elements),
          layout: SourceListLayout(directives: directives),
          when: condition
        )
      } else {
        let nodes = try components.map { component -> SourceLayout.Node in
          switch component {
          case let .layout(layout): return layout.node
          case let .separator(whitespace):
            try Self.validate(whitespace)
            return whitespace == .blankLine ? .blankLine : .newline
          case .group, .blankLine, .newline, .sequence:
            throw SourceListLayoutError.mixedContent
          }
        }
        guard !elements.isEmpty else {
          _ = try SourceLayout(node: .sequence(nodes)).sources
          correction = .notApplicable
          return
        }
        fix = SourceFix(proposedEdits: [try SourceLayoutReplacement.make(
          elements: elements.map(\.self),
          layout: SourceLayout(node: .sequence(nodes)),
          when: condition
        )])
      }
      correction = elements.isEmpty ? .notApplicable : SourceCorrection(fix)
    } catch let error as SourceCorrectionError {
      correction = switch error {
      case let .unavailable(reason): .unavailable(reason)
      case let .undetermined(reason): .undetermined(reason)
      }
    }
  }

  /// Arranges a source list with a stored explicit layout.
  public init(
    _ elements: some Collection<Element>,
    layout: SourceLayout,
    when condition: SourceLayoutCondition? = nil
  ) throws {
    try self.init(
      elements,
      layout: .layout(layout),
      when: condition
    )
  }

  private static func validate(_ whitespace: SourceWhitespace) throws {
    guard whitespace == .newline || whitespace == .blankLine else {
      throw SourceListLayoutError.unsupportedSeparator
    }
  }
}
