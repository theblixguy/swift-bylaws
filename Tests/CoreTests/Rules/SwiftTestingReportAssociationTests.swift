import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Testing report associations")
struct SwiftTestingReportAssociationTests {
  @Test(
    "Round-trips retain checks offenders and cross-file edits",
    arguments: [false, true]
  )
  func associations(diskBacked: Bool) throws {
    let project = try TemporaryProject(files: [
      "Sources/Alpha.swift": "// café 👋\r\nclass Alpha {}\r\n",
      "Sources/Beta.swift": "// cafe\u{301} 🐈\nstruct Beta {}\n",
    ])
    let report = try report(in: project)
    let decoded: SwiftTestingRuleReport
    if diskBacked {
      let directory = project.rootURL.appendingPathComponent("reports")
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true
      )
      let session = SwiftTestingRuleSession(
        id: "associations", directory: directory.path,
        rootPath: project.rootURL.path
      )
      try session.write(report)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("report-") }
      try #require(files.count == 1)
      let file = try #require(files.first)
      decoded = try SwiftTestingRuleSession.readReport(at: file)
    } else {
      decoded = try JSONDecoder().decode(
        SwiftTestingRuleReport.self, from: JSONEncoder().encode(report)
      )
    }

    let alphaPath = project.fileURL(for: "Sources/Alpha.swift").path
    let betaPath = project.fileURL(for: "Sources/Beta.swift").path
    #expect(decoded.sessionID == "associations")
    #expect(decoded.testID == "association-test")
    #expect(decoded.ruleID == "declarations")
    #expect(decoded.baselineAccepted == [false, true, false])
    try #require(decoded.checks.count == 2)
    let names = decoded.checks[0]
    #expect(names.rule == "use paired names")
    #expect(names.checkedCount == 4)
    #expect(names.offenders.map(\.name) == ["Alpha", "Beta"])
    #expect(names.offenders.map(\.location.filePath) == [alphaPath, betaPath])
    #expect(names.offenders.map(\.location.column) == [7, 8])
    try #require(names.fixes.count == 2)
    #expect(names.fixes[1] == nil)
    let rename = try #require(names.fixes[0])
    #expect(rename.title == "Rename paired declarations")
    try #require(rename.edits.count == 2)
    expectEdit(
      rename.edits[0], path: alphaPath,
      originalSource: "// café 👋\r\nclass Alpha {}\r\n",
      languageMode: .v5, range: 21..<26, text: "Alpha", replacement: "Primary"
    )
    expectEdit(
      rename.edits[1], path: betaPath,
      originalSource: "// cafe\u{301} 🐈\nstruct Beta {}\n",
      languageMode: .v6, range: 22..<26, text: "Beta", replacement: "Companion"
    )

    let kinds = decoded.checks[1]
    #expect(kinds.rule == "use classes")
    #expect(kinds.checkedCount == 2)
    #expect(kinds.offenders.map(\.name) == ["Beta"])
    #expect(kinds.offenders.map(\.location.filePath) == [betaPath])
    #expect(kinds.offenders.map(\.location.column) == [8])
    try #require(kinds.fixes.count == 1)
    let changeKind = try #require(kinds.fixes[0])
    #expect(changeKind.title == "Change declaration kinds")
    try #require(changeKind.edits.count == 2)
    expectEdit(
      changeKind.edits[0], path: betaPath,
      originalSource: "// cafe\u{301} 🐈\nstruct Beta {}\n",
      languageMode: .v6, range: 15..<21, text: "struct", replacement: "class"
    )
    expectEdit(
      changeKind.edits[1], path: alphaPath,
      originalSource: "// café 👋\r\nclass Alpha {}\r\n",
      languageMode: .v5, range: 15..<20, text: "class",
      replacement: "final class"
    )
  }

  private func report(in project: TemporaryProject) throws
    -> SwiftTestingRuleReport
  {
    let alphaPath = project.fileURL(for: "Sources/Alpha.swift").path
    let betaPath = project.fileURL(for: "Sources/Beta.swift").path
    let alpha = SourceSnapshot(
      filePath: alphaPath, text: "// café 👋\r\nclass Alpha {}\r\n",
      swiftLanguageMode: .v5
    )
    let beta = SourceSnapshot(
      filePath: betaPath, text: "// cafe\u{301} 🐈\nstruct Beta {}\n",
      swiftLanguageMode: .v6
    )
    let alphaOffender = Offender(
      description: "class Alpha", name: "Alpha",
      location: .init(filePath: alphaPath, line: 2, column: 7)
    )
    let betaOffender = Offender(
      description: "struct Beta", name: "Beta",
      location: .init(filePath: betaPath, line: 2, column: 8)
    )
    let rename = try SourceFix("Rename paired declarations", edits: [
      SourceSlice(snapshot: alpha, range: 21..<26).replacement(with: "Primary"),
      SourceSlice(snapshot: beta, range: 22..<26)
        .replacement(with: "Companion"),
    ])
    let changeKind = try SourceFix("Change declaration kinds", edits: [
      SourceSlice(snapshot: beta, range: 15..<21).replacement(with: "class"),
      SourceSlice(snapshot: alpha, range: 15..<20)
        .replacement(with: "final class"),
    ])
    return SwiftTestingRuleReport(
      sessionID: "associations", testID: "association-test",
      ruleID: "declarations", name: "Declaration conventions",
      enforcement: .enforced, hint: nil,
      location: .init(
        filePath: project.fileURL(for: "Tests/RuleTests.swift").path,
        line: 3, column: 1
      ),
      findings: Rule.Findings(checks: [
        Violations(
          rule: "use paired names", offenders: [alphaOffender, betaOffender],
          checkedCount: 4, witnesses: [nil, nil], fixes: [rename, nil]
        ),
        Violations(
          rule: "use classes", offenders: [betaOffender],
          checkedCount: 2, witnesses: [nil], fixes: [changeKind]
        ),
      ]),
      baselineAccepted: [false, true, false], origin: nil
    )
  }

  private func expectEdit(
    _ edit: SourceFix.Edit,
    path: String,
    originalSource: String,
    languageMode: SwiftLanguageMode,
    range: Range<Int>,
    text: String,
    replacement: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(edit.source.filePath == path, sourceLocation: sourceLocation)
    #expect(
      edit.source.file.text.utf8.elementsEqual(originalSource.utf8),
      sourceLocation: sourceLocation
    )
    #expect(
      edit.source.snapshot.swiftLanguageMode == languageMode,
      sourceLocation: sourceLocation
    )
    #expect(edit.source.range == range, sourceLocation: sourceLocation)
    #expect(
      edit.source.text.utf8.elementsEqual(text.utf8),
      sourceLocation: sourceLocation
    )
    #expect(
      edit.replacement.utf8.elementsEqual(replacement.utf8),
      sourceLocation: sourceLocation
    )
  }
}
