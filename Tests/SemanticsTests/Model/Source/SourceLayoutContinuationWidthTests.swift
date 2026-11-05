import Testing
@testable import BylawsSemantics

@Suite("Continuation width")
struct SourceLayoutContinuationWidthTests {
  @Test("Maximum columns and tab widths do not overflow", arguments: [
    ("a", Int.max, 4),
    ("\t", Int.max, Int.max),
    ("a\t", 1, Int.max),
  ])
  func maximumColumns(text: String, column: Int, tabWidth: Int) {
    let following = continuation([])

    #expect(following.matches(
      .maximumLineLength(Int.max...Int.max), after: text,
      startingAt: column, tabWidth: tabWidth
    ))
    #expect(!following.matches(
      !.maximumLineLength(...Int.max), after: text,
      startingAt: column, tabWidth: tabWidth
    ))
  }

  @Test(
    "Bounded conditions measure complete graphemes and tab stops",
    arguments: [
      ("e", ["\u{0301}"], 4),
      ("👩", ["\u{200D}", "🔬"], 4),
      ("x", ["\t", "z"], 9),
      ("x\r\n", ["unrelatedLongLine"], 4),
      ("abcdef\r\nx", ["y"], 9),
    ]
  )
  func boundedLength(prefix: String, segments: [String], length: Int) {
    let following = continuation(segments)

    #expect(following.matches(
      .maximumLineLength(length...length), after: prefix,
      startingAt: 3, tabWidth: 4
    ))
    #expect(!following.matches(
      .maximumLineLength(..<length), after: prefix,
      startingAt: 3, tabWidth: 4
    ))
  }

  @Test(
    "Width retains graphemes across source and continuation segments",
    arguments: [
      ("e", ["\u{0301}"], 4, false),
      ("e", ["\u{0301}"], 3, true),
      ("👩", ["\u{200D}", "🔬"], 4, false),
      ("👩", ["\u{200D}", "🔬"], 3, true),
      ("x", ["🇬", "🇧"], 5, false),
      ("x", ["🇬", "🇧"], 4, true),
    ]
  )
  func graphemes(
    prefix: String, segments: [String], maximumWidth: Int, expected: Bool
  ) {
    let following = continuation(segments)

    #expect(following.matches(
      !.maximumLineLength(...maximumWidth), after: prefix, startingAt: 3,
      tabWidth: 4
    ) == expected)
  }

  @Test(
    "Width uses configured tab stops across continuation segments",
    arguments: [(4, 5, false), (4, 4, true), (8, 9, false), (8, 8, true)]
  )
  func tabs(tabWidth: Int, maximumWidth: Int, expected: Bool) {
    let following = continuation(["\t", "z"])

    #expect(following.matches(
      !.maximumLineLength(...maximumWidth), after: "a", startingAt: 1,
      tabWidth: tabWidth
    ) == expected)
  }

  @Test(
    "Width stops continuation at a physical newline",
    arguments: ["\n", "\r\n", "\r"], [(3, false), (2, true)]
  )
  func continuationNewline(
    ending: String, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = continuation([ending, "unreasonablyLongSuffix"])

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "ab", startingAt: 1,
      tabWidth: 4
    ) == testCase.expected)
  }

  @Test(
    "Width resets source columns after physical newlines",
    arguments: ["\n", "\r\n", "\r"], [(4, false), (3, true)]
  )
  func sourceNewline(
    ending: String, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = continuation(["z", "z"])

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "a\(ending)xy",
      startingAt: 1, tabWidth: 4
    ) == testCase.expected)
  }

  @Test(
    "Width checks preceding source lines before appending continuation",
    arguments: ["\n", "\r\n", "\r"], [(5, false), (4, true)]
  )
  func precedingSourceLine(
    ending: String, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = continuation(["z"])

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "abcd\(ending)x",
      startingAt: 1,
      tabWidth: 4
    ) == testCase.expected)
  }

  @Test(
    "Source ending in a newline excludes continuation width",
    arguments: ["\n", "\r\n", "\r"], [(3, false), (2, true)]
  )
  func sourceTrailingNewline(
    ending: String, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = continuation(["unreasonablyLongSuffix"])

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "ab\(ending)",
      startingAt: 1,
      tabWidth: 4
    ) == testCase.expected)
  }

  @Test(
    "Empty scopes retain a preceding soft boundary",
    arguments: [false, true], [(5, false), (4, true)]
  )
  func emptyScopeSpace(
    hasBoundary: Bool, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = SourceLayoutContinuation.events(
      [.text("a"), .boundary(.soft)][...],
      .scope(
        hasBoundary ? [.boundary(.newline)][...] : [], .init(text: "b")
      )
    )

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "x", startingAt: 1,
      tabWidth: 4
    ) == testCase.expected)
  }

  @Test(
    "Empty scopes retain a preceding newline boundary",
    arguments: [false, true], [(4, false), (3, true)]
  )
  func emptyScopeNewline(
    hasBoundary: Bool, testCase: (maximumWidth: Int, expected: Bool)
  ) {
    let following = SourceLayoutContinuation.events(
      [.text("ab"), .lineBoundary][...],
      .scope(
        hasBoundary ? [.boundary(.soft)][...] : [],
        .init(text: "unreasonablyLongSuffix")
      )
    )

    #expect(following.matches(
      !.maximumLineLength(...testCase.maximumWidth), after: "x", startingAt: 1,
      tabWidth: 4
    ) == testCase.expected)
  }

  @Test("Empty source excludes continuation width")
  func emptySource() {
    let following = continuation(["unreasonablyLongSuffix"])

    #expect(!following.matches(
      !.maximumLineLength(...1), after: "", startingAt: 0, tabWidth: 4
    ))
  }

  private func continuation(_ segments: [String]) -> SourceLayoutContinuation {
    segments.reversed().reduce(.end) { following, text in
      .events([.text(text)][...], following)
    }
  }
}
