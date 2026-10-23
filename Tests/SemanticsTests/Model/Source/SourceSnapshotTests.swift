import BylawsSemantics
import Testing

@Suite("Source snapshot equality")
struct SourceSnapshotTests {
  @Test("Copied snapshots retain equality")
  func sharedText() {
    let original = SourceSnapshot(
      filePath: "/virtual/Store.swift",
      text: String(repeating: "let café = 1\n", count: 256),
      swiftLanguageMode: .v6
    )
    let copy = original

    #expect(original == copy)
    #expect(Set([original, copy]).count == 1)
  }

  @Test("Separately decoded equal source retains equality")
  func separateText() {
    let text = String(repeating: "let café = 1\n", count: 256)
    let first = SourceSnapshot(
      filePath: "/virtual/Store.swift",
      text: text,
      swiftLanguageMode: .v6
    )
    let second = SourceSnapshot(
      filePath: "/virtual/Store.swift",
      text: String(decoding: Array(text.utf8), as: UTF8.self),
      swiftLanguageMode: .v6
    )

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test("Canonical Unicode equality preserves byte differences")
  func canonicalText() {
    let first = SourceSnapshot(
      filePath: "/virtual/Store.swift",
      text: String(repeating: "// café\n", count: 256),
      swiftLanguageMode: .v6
    )
    let second = SourceSnapshot(
      filePath: "/virtual/Store.swift",
      text: String(repeating: "// cafe\u{301}\n", count: 256),
      swiftLanguageMode: .v6
    )

    #expect(first.text == second.text)
    #expect(first != second)
    #expect(Set([first, second]).count == 2)
  }

  @Test("Shared source retains path and language constraints")
  func metadata() {
    let text = String(repeating: "let value = 1\n", count: 256)
    let original = SourceSnapshot(
      filePath: "/virtual/Store.swift", text: text, swiftLanguageMode: .v6
    )
    let otherPath = SourceSnapshot(
      filePath: "/virtual/Other.swift", text: text, swiftLanguageMode: .v6
    )
    let otherMode = SourceSnapshot(
      filePath: "/virtual/Store.swift", text: text, swiftLanguageMode: .v5
    )

    #expect(original != otherPath)
    #expect(original != otherMode)
  }
}
