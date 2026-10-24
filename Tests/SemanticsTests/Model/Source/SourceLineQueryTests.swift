import BylawsSemantics
import Testing

@Suite("Source line widths")
struct SourceLineQueryTests {
  @Test("Widths above limit match", arguments: [
    (4, true), (5, false), (6, false),
  ])
  func threshold(limit: Int, expected: Bool) throws {
    let source = try slice("abcde")

    #expect(source.hasLine(exceeding: limit) == expected)
  }

  @Test("Complete lines include source before and after slice")
  func surroundingText() throws {
    let source = try slice("prefix run() suffix")
      .matches(of: /run\(\)/).only()

    #expect(source.hasLine(exceeding: 18))
    #expect(!source.hasLine(exceeding: 19))
  }

  @Test("Characters occupy one column", arguments: [
    ("café", 4),
    ("cafe\u{301}", 4),
    ("a👩🏽‍💻界", 3),
    ("a\u{2028}b", 3),
  ])
  func characters(text: String, width: Int) throws {
    let source = try slice(text)

    #expect(source.hasLine(exceeding: width - 1))
    #expect(!source.hasLine(exceeding: width))
  }

  @Test("Tabs advance to configured stops", arguments: [
    (8, 8, true), (8, 9, false),
    (4, 4, true), (4, 5, false),
    (0, 2, true), (0, 3, false),
    (-2, 3, false),
  ])
  func tabs(tabWidth: Int, limit: Int, expected: Bool) throws {
    let source = try slice("a\tb")

    #expect(source.hasLine(exceeding: limit, tabWidth: tabWidth) == expected)
  }

  @Test("Default tabs use eight columns")
  func defaultTabs() throws {
    let source = try slice("a\tb")

    #expect(source.hasLine(exceeding: 8))
    #expect(!source.hasLine(exceeding: 9))
  }

  @Test("Large tab widths compare without overflow")
  func largeTabs() throws {
    let source = try slice("\tx")

    #expect(source.hasLine(exceeding: Int.max, tabWidth: Int.max))
  }

  @Test("Projected text starts at supplied column")
  func projectedColumn() {
    #expect(SourceTextWidth.exceeds(8, in: "a\tb", startingAt: 3, tabWidth: 4))
    #expect(!SourceTextWidth.exceeds(9, in: "a\tb", startingAt: 3, tabWidth: 4))
  }

  @Test("Physical line endings contribute no width", arguments: [
    "\n", "\r\n", "\r",
  ])
  func lineEndings(ending: String) throws {
    let source = try slice("short\(ending)longest\(ending)x")
    let firstLine = try source.slice(0..<(5 + ending.utf8.count))
    let endingOnly = try source.slice(5..<(5 + ending.utf8.count))
    let secondLine = try source.slice((5 + ending.utf8.count)..<source.range
      .count)

    #expect(!firstLine.hasLine(exceeding: 5))
    #expect(endingOnly.hasLine(exceeding: 4))
    #expect(!endingOnly.hasLine(exceeding: 5))
    #expect(secondLine.hasLine(exceeding: 6))
    #expect(!secondLine.hasLine(exceeding: 7))
    #expect(!source.hasLine(exceeding: 7))
  }

  @Test("CRLF second byte belongs to preceding line")
  func crlfBoundary() throws {
    let source = try slice("short\r\nlongest")
    let lineFeed = try source.slice(6..<7)

    #expect(lineFeed.hasLine(exceeding: 4))
    #expect(!lineFeed.hasLine(exceeding: 5))
  }

  @Test("Untouched neighbouring lines stay outside query")
  func neighbouringLines() throws {
    let source = try slice("longBefore\nx\nlongAfter")
      .matches(of: /x/).only()

    #expect(!source.hasLine(exceeding: 1))
  }

  @Test("Short multiline source stays below limit")
  func multiline() throws {
    let source = try slice("send(\n  first: 1,\n  second: 2\n)")

    #expect(!source.hasLine(exceeding: 12))
    #expect(source.hasLine(exceeding: 10))
  }

  @Test("Empty ranges touch no lines", arguments: [0, 2, 5])
  func emptyRange(offset: Int) throws {
    let source = try slice("abcd\n").slice(offset..<offset)

    #expect(!source.hasLine(exceeding: -1))
  }

  @Test("Empty file touches no lines")
  func emptyFile() throws {
    #expect(try !slice("").hasLine(exceeding: -1))
  }

  @Test("Empty physical line has zero width")
  func emptyLine() throws {
    let source = try slice("\n")

    #expect(source.hasLine(exceeding: -1))
    #expect(!source.hasLine(exceeding: 0))
  }

  private func slice(_ text: String) throws -> SourceSlice {
    try SourceSlice(
      snapshot: SourceSnapshot(
        filePath: "/virtual/Lines.swift", text: text,
        swiftLanguageMode: .v6
      ),
      range: 0..<text.utf8.count
    )
  }
}
