import BylawsSyntax

extension SourceLayoutComposition.Session {
  func contentEdits(in edits: [SourceFix.Edit]) throws -> [SourceFix.Edit] {
    try edits.flatMap { edit in
      guard let plan = edit.layout else { return [edit] }
      let captured = try plan.thaw(snapshot: snapshot).edits
        + plan.nested.map { try $0.thaw(snapshot: snapshot) }
      return try contentEdits(in: captured)
    }
  }

  func render(
    _ edit: SourceFix.Edit,
    at placement: SourceLayoutRenderer.Placement? = nil
  ) throws -> String {
    guard let plan = edit.layout else { return edit.replacement }
    let elements = try plan.elements.map {
      try SourceSlice(snapshot: snapshot, range: $0)
    }
    let nested = try plan.nested.map { try $0.thaw(snapshot: snapshot) }
    let result = try SourceLayoutReplacement.make(
      elements: elements,
      layout: plan.thaw(snapshot: snapshot), parsedTree: tree,
      allowsPartialList: plan.allowsPartialList,
      baseIndentation: plan.baseIndentation,
      nested: nested, placement: placement,
      whenLineExceeds: plan.lineWidthLimit
    )
    if plan.trimmed {
      return String(result.replacement.drop(while: isWhitespace).reversed()
        .drop(while: isWhitespace).reversed())
    }
    guard result.source.range == edit.source.range else {
      throw SourceError.syntaxMismatch
    }
    return result.replacement
  }

  func content(
    _ source: SourceSlice, applying edits: [SourceFix.Edit],
    at placement: SourceLayoutRenderer.Placement
  ) throws -> String {
    let originalIndentation = SourceLayoutText.indentation(
      in: bytes,
      before: source.range.lowerBound
    )
    let projected = try SourceLayoutText(
      source.text,
      originalIndentation: originalIndentation,
      indentation: placement.indentation
    )
    let roots = try compose(edits: edits, validating: false)
    guard roots.allSatisfy({
      $0.source.range.lowerBound >= source.range.lowerBound
        && $0.source.range.upperBound <= source.range.upperBound
    }) else { throw SourceError.rangeOutOfBounds }
    let projectedBytes = Array(projected.text.utf8)
    let rawEdits = try contentEdits(in: roots).sorted {
      $0.source.range.lowerBound < $1.source.range.lowerBound
    }
    var nextRawEdit = 0
    var result = ""
    var cursor = 0
    var column = placement.column
    var lineIndentation = placement.lineIndentation
    func append(_ value: String) {
      let wasIndentation = column == SourceTextWidth
        .column(after: lineIndentation)
      result += value
      column = SourceTextWidth.column(after: value, startingAt: column)
      if value.contains(where: SourceLayoutText.isNewline) {
        lineIndentation = SourceLayoutText
          .indentation(in: SourceLayoutText.lastLine(in: result))
      } else if wasIndentation {
        lineIndentation += SourceLayoutText.indentation(in: value)
      }
    }
    for edit in roots {
      let lower = try projected
        .offset(edit.source.range.lowerBound - source.range.lowerBound)
      let upper = try projected
        .offset(edit.source.range.upperBound - source.range.lowerBound)
      let prefix = String(
        decoding: projectedBytes[cursor..<lower],
        as: UTF8.self
      )
      append(prefix)
      let original = String(
        decoding: projectedBytes[lower..<upper],
        as: UTF8.self
      )
      while nextRawEdit < rawEdits.count,
            rawEdits[nextRawEdit].source.range.lowerBound < edit.source.range
              .upperBound
      {
        nextRawEdit += 1
      }
      let suffix = try lineSuffix(
        after: upper, in: projected, bytes: projectedBytes,
        originalStart: source.range.lowerBound,
        applying: rawEdits[nextRawEdit...], followedBy: placement.trailingText
      )
      let childPlacement = SourceLayoutRenderer.Placement(
        column: column, indentation: placement.indentation,
        lineIndentation: lineIndentation, originalText: original,
        trailingText: suffix
      )
      let replacement: String = if edit.layout != nil {
        try render(edit, at: childPlacement)
      } else {
        try SourceLayoutText(
          edit.replacement,
          originalIndentation: originalIndentation,
          indentation: placement.indentation
        ).text
      }
      append(replacement)
      cursor = upper
    }
    result += String(decoding: projectedBytes[cursor...], as: UTF8.self)
    return result
  }

  private func lineSuffix(
    after start: Int, in projected: SourceLayoutText, bytes: [UInt8],
    originalStart: Int, applying edits: ArraySlice<SourceFix.Edit>,
    followedBy trailingText: String
  ) throws -> String {
    var result = ""
    var cursor = start
    func append(_ bytes: some Collection<UInt8>) -> Bool {
      let line = bytes.prefix { $0 != 10 && $0 != 13 }
      result += String(decoding: line, as: UTF8.self)
      return line.count < bytes.count
    }
    for edit in edits {
      let lower = try projected
        .offset(edit.source.range.lowerBound - originalStart)
      let upper = try projected
        .offset(edit.source.range.upperBound - originalStart)
      guard lower >= cursor else { throw SourceError.overlappingEdits }
      if append(bytes[cursor..<lower]) ||
        append(edit.replacement.utf8) { return result }
      cursor = upper
    }
    if append(bytes[cursor...]) { return result }
    return result + trailingText
  }

  private func isWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || SourceLayoutText
      .isNewline(character)
  }
}
