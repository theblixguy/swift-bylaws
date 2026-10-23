import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction cookbook")
struct CorrectionCookbookTests {
  @Test(
    "Portable recipe corrects source and passes on second run",
    arguments: CorrectionCookbookMock.cases
  )
  func portableRecipe(mock: CorrectionCookbookMock) async throws {
    let source = try ruleSource(article: mock.article, ruleID: mock.ruleID)
    let files = mock.sources.merging([
      "Package.swift": "",
      "Bylaws.swift": source,
    ]) { _, replacement in replacement }
    let project = try TemporaryProject(files: files)
    let program = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    try #require(program.rules.count == 1)
    let rule = try #require(program.rules.first)
    #expect(rule.id.rawValue == mock.ruleID)
    let findings = try await rule.findings()
    let edits = findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
    try #require(!edits.isEmpty)
    let paths = Set(mock.expected.keys.map { project.fileURL(for: $0).path })
    #expect(Set(edits.map(\.source.filePath)).isSubset(of: paths))

    for (path, expected) in mock.expected {
      let original = try #require(mock.sources[path])
      let absolutePath = project.fileURL(for: path).path
      let fileEdits = edits.filter { $0.source.filePath == absolutePath }
      if let first = fileEdits.first {
        #expect(first.source.file.text == original)
      }
      let actual = if let first = fileEdits.first {
        try first.source.file.replacement(applying: fileEdits)
          .replacement
      } else {
        original
      }
      #expect(actual == expected, "\(mock.ruleID): \(path)")
      try project.write(actual, to: path)
    }
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let updated = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    try #require(updated.rules.count == 1)
    let verified = try await #require(updated.rules.first).findings()

    #expect(verified.violations.isEmpty)
    #expect(verified.violations.fixes.compactMap(\.self).isEmpty)
  }

  private func ruleSource(article: String, ruleID: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let path = root.appendingPathComponent(
      "Sources/Bylaws/Bylaws.docc/\(article).md"
    )
    let article = try String(contentsOf: path, encoding: .utf8)
    let blocks = article.components(separatedBy: "```swift\n").dropFirst()
      .compactMap { $0.components(separatedBy: "\n```").first }
      .filter { $0.contains("Rule(\"\(ruleID)\"") }
    try #require(blocks.count == 1)
    return try #require(blocks.first)
  }
}
