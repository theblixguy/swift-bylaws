import BylawsSyntax

extension Collection where Element: SourceProviding {
  /// Returns a layout replacement for a contiguous source list.
  ///
  /// The collection must be nonempty and come from one snapshot of a file.
  /// It can contain attributes, modifiers, members, statements, call arguments,
  /// parameters, enum case elements or array and dictionary elements.
  /// The `elements` projection also supports conditions, generic clauses,
  /// inherited types, tuples, closure signatures, accessors and switch cases.
  /// Attribute, modifier and comma-separated lists must be complete. Member
  /// and statement lists can be consecutive regions within a larger list.
  ///
  /// The layout must emit every input element exactly once. A replacement
  /// retains each input element and regenerates list separators. An embedded
  /// edit can change part of one element. The fix stops at
  /// conditional-compilation boundaries or when a comment's ownership is unclear.
  ///
  /// Space indentation comes from source outside the replaced list, with two
  /// spaces used when none can be inferred. Tabs use one tab per level.
  /// Wrapping defaults to 100 characters.
  ///
  /// The default `nil` condition applies the layout unconditionally. A nested
  /// layout checks its condition at its new position in the containing layout.
  /// - Throws: ``SourceError`` when captured source cannot be read,
  ///   ``SourceLayoutReplacementError`` for unsupported input or source
  ///   ownership, or ``SourceLayoutError`` for a layout that cannot be rendered.
  ///   Errors from `layout` also propagate to the caller.
  public func replacement(
    when condition: SourceLayoutCondition? = nil,
    @SourceLayoutBuilder _ layout: () throws -> SourceLayout
  ) throws -> SourceFix.Edit {
    try SourceLayoutReplacement.make(
      elements: map(\.self), layout: layout(), when: condition
    )
  }

  /// Returns a replacement using a stored layout and an optional condition.
  public func replacement(
    layout: SourceLayout, when condition: SourceLayoutCondition? = nil
  ) throws -> SourceFix.Edit {
    try SourceLayoutReplacement.make(
      elements: map(\.self),
      layout: layout,
      when: condition
    )
  }
}

package enum SourceLayoutReplacement {
  package static func make(
    elements: [any SourceProviding], layout: SourceLayout,
    when condition: SourceLayoutCondition? = nil
  ) throws -> SourceFix.Edit {
    try make(
      elements: elements, layout: layout, parsedTree: nil,
      when: condition
    )
  }

  static func make(
    elements: [any SourceProviding], layout: SourceLayout,
    parsedTree: SourceFileSyntax?, allowsPartialList: Bool = false,
    sourceContext: Context? = nil, baseIndentation: String? = nil,
    when condition: SourceLayoutCondition? = nil,
    lineEnding: String? = nil
  ) throws -> SourceFix.Edit {
    let prepared = try prepare(
      elements: elements, layout: layout, parsedTree: parsedTree,
      allowsPartialList: allowsPartialList, sourceContext: sourceContext,
      baseIndentation: baseIndentation,
      when: condition, lineEnding: lineEnding
    )
    return SourceFix.Edit(
      source: prepared.source,
      replacement: try SourceLayoutRenderer.render(prepared),
      layout: prepared.capture
    )
  }
}
