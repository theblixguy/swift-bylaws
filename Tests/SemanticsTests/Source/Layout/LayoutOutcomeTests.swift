import BylawsSemantics
import Testing

@Suite("Layout correction outcomes")
struct LayoutOutcomeTests {
  @Test(
    "Unknown applicability takes precedence over unavailable fixes",
    arguments: [false, true],
    [false, true]
  )
  func unknownOutcome(grouped: Bool, unknownFirst: Bool) throws {
    let file = try FileCollector.collect(
      source: "let result = send(first: 1, second: 2)",
      path: "/virtual/Calls.swift"
    )
    let arguments = try #require(file.calls.first).arguments
    let unknown = SourceLayout {
      Indent {
        SourceCorrection.undetermined("The enclosing context is unknown.")
      }
    }
    let unavailable =
      SourceCorrection
        .unavailable("The comment has no clear owner.")
    let operation = try Layout(arguments) {
      if grouped { Group { _ in true } } else { arguments }
      if unknownFirst { unknown }
      unavailable
      if !unknownFirst { unknown }
    }

    #expect(operation.correction.outcome == .undetermined)
    #expect(operation.correction.reason == "The enclosing context is unknown.")
    #expect(operation.correction.fix == nil)
    #expect(
      throws:
      SourceCorrectionError
        .undetermined("The enclosing context is unknown.")
    ) {
      try arguments.replacement {
        unavailable
        unknown
      }
    }
  }

  @Test("Grouped layouts retain an unavailable correction")
  func unavailablePolicy() throws {
    let operation = try Layout([UnreadSource()]) {
      Group { _ in true }
      SourceCorrection.unavailable("The comment has no clear owner.")
    }

    #expect(operation.correction.outcome == .violation)
    #expect(operation.correction.reason == "The comment has no clear owner.")
    #expect(operation.correction.fix == nil)
  }

  @Test("Nonmatching policies validate source access")
  func unmatchedSource() throws {
    #expect(throws: SourceError.unavailable) {
      try Layout([UnreadSource(), UnreadSource()]) {
        Group { _ in false }
        BlankLine(before: { _ in false })
      }
    }
    #expect(throws: SourceListLayoutError.unsupportedSeparator) {
      try Layout(
        [UnreadSource()],
        layout: .sequence([
          .group(Group { _ in false }), .separator(.space),
        ])
      )
    }
  }

  private struct UnreadSource: SourceProviding {
    var source: SourceSlice {
      get throws { throw SourceError.unavailable }
    }
  }
}
