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
    arguments: CorrectionCookbookMock.cases + CorrectionCookbookMock
      .formattingCases
  )
  func portableRecipe(mock: CorrectionCookbookMock) async throws {
    let source = try mock.bylawsSource()
    let files = mock.sources.merging([
      "Package.swift": "",
      "Bylaws.swift": source,
    ]) { _, replacement in replacement }
    let project = try TemporaryProject(files: files)
    let program = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    try #require(program.rules.count == mock.ruleIDs.count)
    #expect(Set(program.rules.map(\.id.rawValue)) == Set(mock.ruleIDs))
    var edits: [SourceFix.Edit] = []
    var layoutCandidates: [SourceFix.Edit] = []
    for rule in program.rules {
      let findings = try await rule.findings()
      try #require(!findings.violations.isEmpty, "\(rule.id)")
      edits += findings.violations.fixes.compactMap(\.self).flatMap(\.edits)
      layoutCandidates += findings.violations.layoutCandidates
    }
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
        try first.source.file.replacement(
          applying: fileEdits,
          layoutCandidates: layoutCandidates.filter {
            $0.source.filePath == absolutePath
          }
        )
        .replacement
      } else {
        original
      }
      #expect(actual == expected, "\(mock.testDescription): \(path)")
      try project.write(actual, to: path)
    }
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let updated = try await loadedProgram(
      in: project,
      rulesFile: "Bylaws.swift"
    )
    try #require(updated.rules.count == mock.ruleIDs.count)
    #expect(Set(updated.rules.map(\.id.rawValue)) == Set(mock.ruleIDs))
    for rule in updated.rules {
      let verified = try await rule.findings()
      #expect(verified.violations.isEmpty, "\(rule.id)")
      #expect(
        verified.violations.fixes.compactMap(\.self).isEmpty,
        "\(rule.id)"
      )
    }
  }
}
