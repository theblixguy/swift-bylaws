import Bylaws
import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Testing layout context transport")
struct SwiftTestingLayoutCandidateCodingTests {
  @Test(
    "Passing check shares one snapshot for retained layout context",
    arguments: [false, true]
  )
  func passingPolicy(diskBacked: Bool) async throws {
    let check = try await passingCheck()
    let report = report(check)
    let decoded: SwiftTestingRuleReport
    if diskBacked {
      let project = try TemporaryProject(files: [:])
      let session = SwiftTestingRuleSession(
        id: "run", directory: project.rootURL.path,
        rootPath: project.rootURL.path
      )
      try session.write(report)
      let file = try #require(FileManager.default.contentsOfDirectory(
        at: project.rootURL, includingPropertiesForKeys: nil
      ).first { $0.lastPathComponent.hasPrefix("report-") })
      let payload = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: file)
      ) as? [String: Any])
      #expect((payload["snapshotIDs"] as? [String])?.count == 1)
      decoded = try SwiftTestingRuleSession.readReport(at: file)
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
    let restored = try #require(decoded.checks.first)
    let candidate = try #require(restored.layoutCandidates.first)

    #expect(decoded.checks.count == 1)
    #expect(restored.checkedCount == 1)
    #expect(restored.offenders.isEmpty)
    #expect(restored.fixes.isEmpty)
    #expect(restored.layoutCandidates.count == 1)
    #expect(candidate.layout != nil)
    #expect(candidate.source.text == "@Observable @MainActor\n")
    #expect(candidate.replacement == "@Observable @MainActor\n")
    #expect(restored == check)
  }

  @Test("Report decoder rejects layout context without a plan")
  func unplannedCandidate() async throws {
    let original = report(try await passingCheck())
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(original)
    ) as? [String: Any])
    var checks = try #require(payload["checks"] as? [[String: Any]])
    var check = try #require(checks.first)
    var candidates = try #require(check["layoutCandidates"] as? [[String: Any]])
    var candidate = try #require(candidates.first)
    candidate.removeValue(forKey: "layout")
    candidates[0] = candidate
    check["layoutCandidates"] = candidates
    checks[0] = check
    payload["checks"] = checks
    let data = try JSONSerialization.data(withJSONObject: payload)

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try JSONDecoder().decode(SwiftTestingRuleReport.self, from: data)
    }
    #expect(error
      .description ==
      "SourceLayout context must preserve the original bytes. Report a changed layout as a correction.")
  }

  @Test("Fix context stays with its offender through report transport")
  func fixContext() async throws {
    let original = report(try await fixCheck())
    let data = try JSONEncoder().encode(original)
    let payload = try #require(JSONSerialization
      .jsonObject(with: data) as? [String: Any])
    let decoded = try JSONDecoder().decode(
      SwiftTestingRuleReport.self,
      from: data
    )
    let restored = try #require(decoded.checks.first)
    let fix = try #require(restored.fixes.first ?? nil)
    let candidate = try #require(fix.layoutCandidates.first)

    #expect((payload["snapshots"] as? [Any])?.count == 1)
    #expect(restored.offenders.map(\.name) == ["Screen"])
    #expect(restored.layoutCandidates.isEmpty)
    #expect(fix.edits.map(\.source.text) == ["Screen"])
    #expect(fix.edits.map(\.replacement) == ["Updated"])
    #expect(fix.layoutCandidates.count == 1)
    #expect(candidate.source.text == "@Observable @MainActor\n")
    try candidate.validateLayoutCandidate()
  }

  @Test("Report decoder rejects fix context without a plan")
  func unplannedFixContext() async throws {
    let original = report(try await fixCheck())
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(original)
    ) as? [String: Any])
    var checks = try #require(payload["checks"] as? [[String: Any]])
    var check = try #require(checks.first)
    var fixes = try #require(check["fixes"] as? [[String: Any]])
    var fix = try #require(fixes.first)
    var candidates = try #require(fix["layoutCandidates"] as? [[String: Any]])
    var candidate = try #require(candidates.first)
    candidate.removeValue(forKey: "layout")
    candidates[0] = candidate
    fix["layoutCandidates"] = candidates
    fixes[0] = fix
    check["fixes"] = fixes
    checks[0] = check
    payload["checks"] = checks
    let data = try JSONSerialization.data(withJSONObject: payload)

    let error = try #require(throws: SourceLayoutComposition.Failure.self) {
      try JSONDecoder().decode(SwiftTestingRuleReport.self, from: data)
    }
    #expect(error.description ==
      "SourceLayout context must preserve the original bytes. Report a changed layout as a correction.")
  }

  private func fixCheck() async throws -> Violations<Offender> {
    let passing = try await passingCheck()
    let candidate = try #require(passing.layoutCandidates.first)
    let name = try candidate.source.file.matches(of: /Screen/).only()
    return Violations(
      rule: "Rename screen", offenders: [Offender(
        description: "Screen", name: "Screen",
        location: .start(of: name.filePath)
      )], checkedCount: 1, witnesses: [nil],
      fixes: [SourceFix(
        edits: [name.replacement(with: "Updated")],
        layoutCandidates: [candidate]
      )]
    )
  }

  private func passingCheck() async throws -> Violations<Offender> {
    let codebase = Codebase(root: .sources([
      "Sources/Screen.swift": "@Observable @MainActor\nclass Screen {}",
    ]))
    return try await codebase.classes
      .violations("Keep attributes") { declaration in
        try declaration.attributes
          .replacement { Line { declaration.attributes } }
      }.erased()
  }

  private func report(_ check: Violations<Offender>) -> SwiftTestingRuleReport {
    SwiftTestingRuleReport(
      sessionID: "run", testID: "test", ruleID: "attributes",
      name: "Attributes use one line", enforcement: .enforced, hint: nil,
      location: .start(of: "/project/Rules.swift"),
      findings: Rule.Findings(violations: check),
      baselineAccepted: Array(repeating: false, count: check.count), origin: nil
    )
  }
}
