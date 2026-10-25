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

  @Test(
    "Report transport retains captured layout policy",
    arguments: [false, true]
  )
  func layoutPolicy(diskBacked: Bool) throws {
    let edit = try layoutEdit()
    let report = try report(source: edit.source.file.text, edits: [edit])
    let decoded: SwiftTestingRuleReport
    if diskBacked {
      let project = try TemporaryProject(files: [:])
      let session = SwiftTestingRuleSession(
        id: "run", directory: project.rootURL.path,
        rootPath: project.rootURL.path
      )
      try session.write(report)
      let stored = try #require(FileManager.default.contentsOfDirectory(
        at: project.rootURL, includingPropertiesForKeys: nil
      ).first { $0.lastPathComponent.hasPrefix("report-") })
      let payload = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: stored)
      ) as? [String: Any])
      #expect((payload["snapshotIDs"] as? [String])?.count == 1)
      decoded = try SwiftTestingRuleSession.readReport(at: stored)
    } else {
      let data = try JSONEncoder().encode(report)
      let payload = try #require(JSONSerialization
        .jsonObject(with: data) as? [String: Any])
      #expect((payload["snapshots"] as? [Any])?.count == 1)
      decoded = try JSONDecoder().decode(
        SwiftTestingRuleReport.self,
        from: data
      )
    }
    let captured = try #require(decoded.checks.first?.fixes.first ?? nil)
      .edits
    try #require(captured.count == 1)
    let restored = try #require(captured.first)

    #expect(restored.layout == edit.layout)
    #expect(restored.source.text == "@MainActor\n@Observable ")
    #expect(restored.replacement == "@Observable @MainActor\n")
    #expect(decoded.checks == report.checks)
  }

  @Test("Report decoding rejects a forged layout preview")
  func forgedLayoutPreview() throws {
    let edit = try layoutEdit()
    let report = try report(source: edit.source.file.text, edits: [edit])
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(report)
    ) as? [String: Any])
    var checks = try #require(payload["checks"] as? [[String: Any]])
    var check = try #require(checks.first)
    var fixes = try #require(check["fixes"] as? [[String: Any]])
    var fix = try #require(fixes.first)
    var edits = try #require(fix["edits"] as? [[String: Any]])
    var altered = try #require(edits.first)
    altered["replacement"] = "@MainActor\n"
    edits[0] = altered
    fix["edits"] = edits
    fixes[0] = fix
    check["fixes"] = fixes
    checks[0] = check
    payload["checks"] = checks
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SwiftTestingRuleReport.self, from: data)
    }
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

  @Test("Snapshot schema errors retain file path and decoder context")
  func snapshotSchema() throws {
    let json = #"{"filePath":"/project/Screen.swift","text":false,"swiftLanguageMode":"6"}"#
    let id = SourceCapture.digest(Data(json.utf8))
    let project = try TemporaryProject(files: ["snapshots/\(id).json": json])
    let snapshot = project.rootURL
      .appendingPathComponent("snapshots/\(id).json")

    #expect {
      try SwiftTestingRuleSession.reportDecoder(in: project.rootURL)
    } throws: { error in
      guard let error = error as? SwiftTestingRuleSessionError,
            case let .malformedReport(reason) = error
      else { return false }
      return reason.contains(snapshot.path)
        && reason.contains("text")
        && reason.contains("String")
    }
  }

  private func report(
    source: String, edits: [SourceFix.Edit]? = nil
  ) throws -> SwiftTestingRuleReport {
    let snapshot = SourceSnapshot(
      filePath: "/project/Screen.swift", text: source,
      swiftLanguageMode: .v6
    )
    let slice = try SourceSlice(snapshot: snapshot, range: 0..<0)
    let fix = SourceFix("Add final", edits: edits ?? [
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

  private func layoutEdit() throws -> SourceFix.Edit {
    let file = try FileCollector.collect(
      source: "@MainActor\n@Observable class Screen {}",
      path: "/project/Screen.swift"
    )
    let attributes = try #require(file.classes.first).attributes
    let layout = SourceLayout { Line { attributes.reversed() } }
    let replacement = try attributes.replacement { layout }
    let plan = try SourceLayoutPlan(
      elements: attributes.map { try $0.source.range },
      node: SourceLayoutPlan.freeze(
        layout,
        snapshot: replacement.source.snapshot
      ),
      targetRange: replacement.source.range
    )
    return SourceFix.Edit(
      source: replacement.source, replacement: replacement.replacement,
      layout: plan
    )
  }
}
