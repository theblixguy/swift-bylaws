import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Swift Testing report source identity")
struct SwiftTestingReportSourceIdentityTests {
  @Test("One path retains different source bytes and language modes")
  func distinctSnapshots() throws {
    let path = "/project/Screen.swift"
    let snapshots = [
      SourceSnapshot(
        filePath: path,
        text: "let café = 1\n",
        swiftLanguageMode: .v6
      ),
      SourceSnapshot(
        filePath: path,
        text: "let cafe\u{301} = 1\n",
        swiftLanguageMode: .v6
      ),
      SourceSnapshot(
        filePath: path,
        text: "let café = 1\n",
        swiftLanguageMode: .v5
      ),
    ]
    let edits = try snapshots.map {
      try SourceSlice(snapshot: $0, range: 0..<0).replacement(with: "private ")
    }
    let original = report(fixes: [
      SourceFix(edits: edits),
      nil,
      SourceFix(edits: [edits[0]]),
    ])

    let data = try JSONEncoder().encode(original)
    let payload = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let decoded = try JSONDecoder().decode(
      SwiftTestingRuleReport.self,
      from: data
    )
    let check = try #require(decoded.checks.first)
    let first = try #require(check.fixes[0])
    let last = try #require(check.fixes[2])

    #expect((payload["snapshots"] as? [Any])?.count == 3)
    #expect(check.fixes.count == 3)
    #expect(check.fixes[1] == nil)
    #expect(first.edits.map(\.source.snapshot.swiftLanguageMode) == [
      .v6,
      .v6,
      .v5,
    ])
    #expect(first.edits.map { Array($0.source.file.text.utf8) } == [
      Array("let café = 1\n".utf8),
      Array("let cafe\u{301} = 1\n".utf8),
      Array("let café = 1\n".utf8),
    ])
    #expect(last.edits.map(\.replacement) == ["private "])
    #expect(last.edits.first?.source.file.text == "let café = 1\n")
  }

  @Test("Later layout with a forged preview fails encoding")
  func forgedLaterPreview() throws {
    let file = try FileCollector.collect(
      source: "@MainActor\n@Observable class Screen {}",
      path: "/project/Screen.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let valid = try attributes.replacement { Line { attributes.reversed() } }
    let forged = SourceFix.Edit(
      source: valid.source, replacement: "@Observable\n", layout: valid.layout
    )

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try JSONEncoder().encode(report(fixes: [
        SourceFix(edits: [valid]), SourceFix(edits: [forged]),
      ]))
    }
    #expect(error.description ==
      "SourceLayout must produce its recorded replacement. Run the rule again.")
  }

  @Test(
    "Changed layout context fails encoding at either owner",
    arguments: [false, true]
  )
  func changedCandidate(checkWide: Bool) throws {
    let file = try FileCollector.collect(
      source: "@MainActor\n@Observable class Screen {}",
      path: "/project/Screen.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let changed = try attributes.replacement { Line { attributes.reversed() } }
    let original = if checkWide {
      report(fixes: [nil], candidates: [changed])
    } else {
      report(fixes: [SourceFix(edits: [], layoutCandidates: [changed])])
    }

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try JSONEncoder().encode(original)
    }
    #expect(error.description ==
      "SourceLayout context must preserve the original bytes. Report a changed layout as a correction.")
  }

  private func report(
    fixes: [SourceFix?], candidates: [SourceFix.Edit] = []
  ) -> SwiftTestingRuleReport {
    let location = DeclarationLocation.start(of: "/project/Screen.swift")
    let offenders = fixes.indices.map { index in
      Offender(
        description: "Screen\(index)",
        name: "Screen\(index)",
        location: location
      )
    }
    return SwiftTestingRuleReport(
      sessionID: "run", testID: "test", ruleID: "attributes",
      name: "Keep attributes", enforcement: .enforced, hint: nil,
      location: location,
      findings: Rule.Findings(checks: [Violations(
        rule: "Keep attributes", offenders: offenders,
        checkedCount: fixes.count,
        witnesses: Array(repeating: nil, count: fixes.count), fixes: fixes,
        layoutCandidates: candidates
      )]),
      baselineAccepted: Array(repeating: false, count: fixes.count), origin: nil
    )
  }
}
