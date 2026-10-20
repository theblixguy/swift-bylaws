import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Testing report source transport")
struct SwiftTestingRuleReportCodingTests {
  @Test("Reports share one exact source snapshot")
  func sharedSnapshots() async throws {
    let project = try TemporaryProject(files: [:])
    let session = SwiftTestingRuleSession(
      id: "run", directory: project.rootURL.path,
      rootPath: project.rootURL.path
    )
    let source = String(repeating: "// cafe\u{301} 👋\r\n", count: 1000)
    let report = try report(source: source)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<12 { group.addTask { try session.write(report) } }
      try await group.waitForAll()
    }

    let snapshots = try FileManager.default.contentsOfDirectory(
      at: project.rootURL.appendingPathComponent("snapshots"),
      includingPropertiesForKeys: nil
    )
    #expect(snapshots.count == 1)
    let files = try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("report-") }
    #expect(files.count == 12)
    let decoder = try SwiftTestingRuleSession.reportDecoder(in: project.rootURL)
    let snapshot = try #require(snapshots.first)
    try FileManager.default.removeItem(at: snapshot)
    for file in files {
      #expect(try Data(contentsOf: file).count < source.utf8.count)
      let decoded = try decoder.decode(
        SwiftTestingRuleReport.self, from: Data(contentsOf: file)
      )
      #expect(decoded.checks == report.checks)
      let text = try #require(decoded.checks.first?.fixes.first ?? nil)
        .edits.first?.source.file.text
      #expect(text?.utf8.elementsEqual(source.utf8) == true)
    }
  }

  @Test("Standalone report stores source once and preserves edits")
  func standaloneRoundTrip() throws {
    let report = try report(source: "let café = \"👋\"\n")
    let data = try JSONEncoder().encode(report)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect((object["snapshots"] as? [Any])?.count == 1)
    let decoded = try JSONDecoder().decode(
      SwiftTestingRuleReport.self,
      from: data
    )
    #expect(decoded.checks == report.checks)
  }

  @Test("Changed stored source blocks report decoding")
  func changedSnapshot() throws {
    let project = try TemporaryProject(files: [:])
    let session = SwiftTestingRuleSession(
      id: "run", directory: project.rootURL.path,
      rootPath: project.rootURL.path
    )
    try session.write(report(source: "class Screen {}"))
    let snapshot = try #require(FileManager.default.contentsOfDirectory(
      at: project.rootURL.appendingPathComponent("snapshots"),
      includingPropertiesForKeys: nil
    ).first)
    try Data("changed".utf8).write(to: snapshot)
    let file = try #require(FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).first { $0.lastPathComponent.hasPrefix("report-") })

    #expect(throws: SwiftTestingRuleSessionError.malformedReport(
      "Source snapshot '\(snapshot.path)' differs from its recorded digest"
    )) {
      try SwiftTestingRuleSession.readReport(at: file)
    }
  }

  private func report(source: String) throws -> SwiftTestingRuleReport {
    let snapshot = SourceSnapshot(
      filePath: "/project/Screen.swift", text: source,
      swiftLanguageMode: .v6
    )
    let slice = try SourceSlice(snapshot: snapshot, range: 0..<0)
    let fix = SourceFix("Add final", edits: [
      slice.replacement(with: "final "),
      slice.replacement(with: "cafe\u{301}"),
    ])
    let offender = Offender(
      description: "class Screen", name: "Screen",
      location: .init(filePath: snapshot.filePath, line: 1, column: 1)
    )
    return SwiftTestingRuleReport(
      sessionID: "run", testID: "test", ruleID: "final-classes",
      name: "Classes are final", enforcement: .enforced, hint: nil,
      location: offender.location,
      findings: Rule.Findings(checks: [Violations(
        rule: "be final", offenders: [offender, offender], checkedCount: 2,
        witnesses: [nil, nil], fixes: [fix, fix]
      )], warnings: []),
      baselineAccepted: [false, false], origin: nil
    )
  }
}
