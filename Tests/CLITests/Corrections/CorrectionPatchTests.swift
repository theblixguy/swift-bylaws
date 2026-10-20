import Foundation
import Testing
@testable import BylawsRunner

@Suite("Correction patches")
struct CorrectionPatchTests {
  @Test("Render empty-file additions and removals", arguments: [
    ("", "let value = 1\n", "@@ -0,0 +1,1 @@\n+let value = 1\n"),
    ("let value = 1\n", "", "@@ -1,1 +0,0 @@\n-let value = 1\n"),
  ])
  func emptyContent(
    original: String,
    replacement: String,
    expectedBody: String
  ) {
    let patch = plan(original: original, replacement: replacement).patch

    #expect(patch == "--- /App.swift\t\n+++ /App.swift\t\n" + expectedBody)
  }

  @Test("Mark missing final newlines independently", arguments: [
    (
      "let value = 1", "let value = 2\n",
      "@@ -1,1 +1,1 @@\n-let value = 1\n\\ No newline at end of file\n+let value = 2\n"
    ),
    (
      "let value = 1\n", "let value = 2",
      "@@ -1,1 +1,1 @@\n-let value = 1\n+let value = 2\n\\ No newline at end of file\n"
    ),
    (
      "let value = 1", "let value = 2",
      "@@ -1,1 +1,1 @@\n-let value = 1\n\\ No newline at end of file\n+let value = 2\n\\ No newline at end of file\n"
    ),
  ])
  func finalNewlines(
    original: String,
    replacement: String,
    expectedBody: String
  ) {
    let patch = plan(original: original, replacement: replacement).patch

    #expect(patch == "--- /App.swift\t\n+++ /App.swift\t\n" + expectedBody)
  }

  @Test("Preserve CRLF source bytes with LF patch headers")
  func carriageReturns() {
    let patch = plan(
      original: "let value = 1\r\n", replacement: "let value = 2\r\n"
    ).patch
    let expected = "--- /App.swift\t\n+++ /App.swift\t\n@@ -1,1 +1,1 @@\n-let value = 1\r\n+let value = 2\r\n"

    #expect(Data(patch.utf8) == Data(expected.utf8))
  }

  @Test("Encode file paths in patch headers", arguments: [
    ("/App.swift", "--- /App.swift\t\n+++ /App.swift\t\n"),
    ("/My App.swift", "--- /My App.swift\t\n+++ /My App.swift\t\n"),
    (
      "/My\tApp.swift",
      "--- \"/My\\tApp.swift\"\t\n+++ \"/My\\tApp.swift\"\t\n"
    ),
    (
      "/My\nApp.swift",
      "--- \"/My\\nApp.swift\"\t\n+++ \"/My\\nApp.swift\"\t\n"
    ),
    (
      "/My\\App.swift",
      "--- \"/My\\\\App.swift\"\t\n+++ \"/My\\\\App.swift\"\t\n"
    ),
    (
      "/My\"App.swift",
      "--- \"/My\\\"App.swift\"\t\n+++ \"/My\\\"App.swift\"\t\n"
    ),
    (
      "/Café.swift",
      "--- \"/Caf\\303\\251.swift\"\t\n+++ \"/Caf\\303\\251.swift\"\t\n"
    ),
    (
      "/Control\u{7}\u{8}\u{b}\u{c}\r\u{1}\u{7f}.swift",
      "--- \"/Control\\a\\b\\v\\f\\r\\001\\177.swift\"\t\n+++ \"/Control\\a\\b\\v\\f\\r\\001\\177.swift\"\t\n"
    ),
  ])
  func pathHeaders(path: String, expectedHeaders: String) {
    let patch = plan(
      original: "let value = 1\n", replacement: "let value = 2\n", path: path
    ).patch

    #expect(patch == expectedHeaders
      + "@@ -1,1 +1,1 @@\n-let value = 1\n+let value = 2\n")
  }

  @Test("Render separate headers and hunks for each changed file")
  func multipleFiles() {
    let plan = CorrectionPlan(
      changes: [
        .init(
          path: "/First.swift", resolvedPath: "/First.swift",
          original: Data("let first = 1\n".utf8),
          replacement: Data("let first = 3\n".utf8)
        ),
        .init(
          path: "/Second.swift", resolvedPath: "/Second.swift",
          original: Data("let second = 2\n".utf8),
          replacement: Data("let second = 4\n".utf8)
        ),
      ],
      diagnostics: [], fixCount: 2
    )
    let expected = """
    --- /First.swift\t
    +++ /First.swift\t
    @@ -1,1 +1,1 @@
    -let first = 1
    +let first = 3
    --- /Second.swift\t
    +++ /Second.swift\t
    @@ -1,1 +1,1 @@
    -let second = 2
    +let second = 4

    """

    #expect(plan.patch == expected)
  }

  private func plan(
    original: String, replacement: String, path: String = "/App.swift"
  ) -> CorrectionPlan {
    CorrectionPlan(
      changes: [.init(
        path: path, resolvedPath: path,
        original: Data(original.utf8), replacement: Data(replacement.utf8)
      )],
      diagnostics: [], fixCount: 1
    )
  }
}
