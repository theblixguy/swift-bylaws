import BylawsSyntax
import Testing
@testable import BylawsSemantics

@Suite("Captured source token lookup")
struct SourceTokenLookupTests {
  @Test(
    "Indexed lookup matches SwiftSyntax across source bytes",
    arguments: [
      "",
      " \r\n// comment\r\n",
      "/* lead */ let café = send(\"🦊\") // tail\r\n",
      "func run() { send(label: nested(1, 2)) }\n",
      "func broken( { let value = \"unfinished",
      "#if DEBUG\nlet value = #inspect(1)\n#endif",
    ]
  )
  func allPositions(text: String) {
    let snapshot = SourceSnapshot(
      filePath: "/virtual/Tokens.swift", text: text, swiftLanguageMode: .v6
    )
    let tree = snapshot.syntaxTree()
    for offset in -1...(text.utf8.count + 1) {
      let expected = tree.token(at: AbsolutePosition(utf8Offset: offset))
      #expect(snapshot.token(at: offset)?.id == expected?.id)
    }
  }

  @Test(
    "Lookup retains token trivia and Unicode boundaries",
    arguments: [
      (-1, nil), (0, "let"), (10, "let"), (14, "let"),
      (15, "café"), (18, "café"), (19, "café"), (20, "café"),
      (21, "="), (22, "="), (23, "1"), (30, "1"),
      (31, ""), (32, ""), (33, nil),
    ] as [(Int, String?)]
  )
  func tokenText(offset: Int, expected: String?) {
    let snapshot = SourceSnapshot(
      filePath: "/virtual/Tokens.swift",
      text: "/* lead */ let café = 1 // end\r\n", swiftLanguageMode: .v6
    )

    #expect(snapshot.token(at: offset)?.text == expected)
  }
}
