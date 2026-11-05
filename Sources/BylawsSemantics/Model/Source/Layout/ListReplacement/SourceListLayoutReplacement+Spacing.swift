import BylawsSyntax

extension SourceListLayoutReplacement {
  static func separators(
    items: [SourceLayoutReplacement.Item],
    operations: [SourceListLayoutOperation]
  ) throws -> SourceFix {
    var requests: [Int: SourceWhitespace] = [:]
    for operation in operations {
      guard case let .conditionalSeparator(gaps, whitespace) = operation
      else { continue }
      for gap in gaps {
        guard gap > 0,
              gap < items.count else { throw SourceError.syntaxMismatch }
        if let existing = requests[gap], existing != whitespace {
          throw SourceListLayoutError.conflictingSeparators
        }
        requests[gap] = whitespace
      }
    }
    guard let first = items.first else { return SourceFix(edits: []) }
    let snapshot = first.source.snapshot
    let bytes = Array(snapshot.text.utf8)
    let lineEnding = snapshot.lineEnding
    var edits: [SourceFix.Edit] = []
    for gap in requests.keys.sorted() {
      guard let whitespace = requests[gap] else { continue }
      let start = items[gap - 1].node.endPositionBeforeTrailingTrivia.utf8Offset
      let end = items[gap].contentRange.lowerBound
      let source = try SourceSlice(snapshot: snapshot, range: start..<end)
      guard source.text.allSatisfy(isWhitespace) else {
        throw SourceLayoutReplacementError.ambiguousTrivia
      }
      var lineStart = end
      while lineStart > 0, bytes[lineStart - 1] != 10,
            bytes[lineStart - 1] != 13
      {
        lineStart -= 1
      }
      let indentation = String(
        decoding: bytes[lineStart..<end].prefix { $0 == 32 || $0 == 9 },
        as: UTF8.self
      )
      let replacement = switch whitespace {
      case .none: ""
      case .space: " "
      case .newline: lineEnding + indentation
      case .blankLine: lineEnding + lineEnding + indentation
      }
      if !source.text.utf8.elementsEqual(replacement.utf8) {
        edits.append(source.replacement(with: replacement))
      }
    }
    return SourceFix(edits: edits)
  }

  static func isWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\n" || character ==
      "\r" || character == "\r\n"
  }
}
