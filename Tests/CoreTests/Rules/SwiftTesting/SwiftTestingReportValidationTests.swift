import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Testing report validation")
struct SwiftTestingReportValidationTests {
  @Test("Decoder rejects malformed report payloads", arguments: [
    (
      PayloadChange.unsupportedVersion,
      SwiftTestingRuleSessionError.unsupportedVersion(99)
    ),
    (.bothSnapshotForms, .malformedReport(
      "The report must contain either source snapshots or snapshot IDs"
    )),
    (.neitherSnapshotForm, .malformedReport(
      "The report must contain either source snapshots or snapshot IDs"
    )),
    (.missingSnapshotStore, .malformedReport(
      "The report decoder must have a source snapshot store"
    )),
    (.missingFix, .malformedReport(
      "The fix count must equal the offender count"
    )),
    (.negativeSnapshotIndex, .malformedReport(
      "Source snapshot index -1 is outside the report's snapshot list"
    )),
    (.pastLastSnapshotIndex, .malformedReport(
      "Source snapshot index 1 is outside the report's snapshot list"
    )),
    (.negativeCheckedCount, .malformedReport(
      "A check count must be zero or greater"
    )),
    (.overflowingCheckedCount, .malformedReport(
      "The check count total exceeds the supported integer range"
    )),
    (.emptySessionID, .malformedReport(
      "The session, test and rule IDs must contain text"
    )),
    (.emptyTestID, .malformedReport(
      "The session, test and rule IDs must contain text"
    )),
    (.emptyRuleID, .malformedReport(
      "The session, test and rule IDs must contain text"
    )),
    (.missingBaselineAcceptance, .malformedReport(
      "The baseline acceptance count must equal the offender count"
    )),
    (.extraBaselineAcceptance, .malformedReport(
      "The baseline acceptance count must equal the offender count"
    )),
  ])
  func malformedPayload(
    change: PayloadChange,
    expectedError: SwiftTestingRuleSessionError
  ) throws {
    let data = try payload(changing: change)

    #expect(throws: expectedError) {
      try JSONDecoder().decode(SwiftTestingRuleReport.self, from: data)
    }
  }

  @Test("Report entry points reject malformed check counts", arguments: [
    ([-1], "A check count must be zero or greater"),
    (
      [Int.max, 1],
      "The check count total exceeds the supported integer range"
    ),
  ])
  func malformedCounts(counts: [Int], reason: String) throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let report = report(checks: counts.map {
      Violations(rule: "be final", offenders: [], checkedCount: $0)
    })
    let expectedError = SwiftTestingRuleSessionError.malformedReport(reason)

    #expect(throws: expectedError) { try report.validate(in: session) }
    #expect(throws: expectedError) { try session.write(report) }
    #expect(throws: expectedError) { try JSONEncoder().encode(report) }
    #expect(try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).isEmpty)
  }

  @Test("Report entry points reject empty identities", arguments: [
    ("", "test", "rule"),
    ("run", "", "rule"),
    ("run", "test", ""),
  ])
  func emptyIdentities(
    sessionID: String,
    testID: String,
    ruleID: String
  ) throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project, id: sessionID)
    let report = report(
      sessionID: sessionID, testID: testID, ruleID: Rule.ID(ruleID)
    )
    let expectedError = SwiftTestingRuleSessionError.malformedReport(
      "The session, test and rule IDs must contain text"
    )

    #expect(throws: expectedError) { try report.validate(in: session) }
    #expect(throws: expectedError) { try session.write(report) }
    #expect(throws: expectedError) { try JSONEncoder().encode(report) }
    #expect(try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).isEmpty)
  }

  @Test(
    "Report entry points reject mismatched baseline acceptance",
    arguments: [
      [Bool](), [false, false],
    ]
  )
  func mismatchedAcceptance(accepted: [Bool]) throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let report = try sourceReport(baselineAccepted: accepted)
    let expectedError = SwiftTestingRuleSessionError.malformedReport(
      "The baseline acceptance count must equal the offender count"
    )

    #expect(throws: expectedError) { try report.validate(in: session) }
    #expect(throws: expectedError) { try session.write(report) }
    #expect(throws: expectedError) { try JSONEncoder().encode(report) }
    #expect(try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    ).isEmpty)
  }

  @Test("Largest supported check total passes report entry points")
  func maximumCount() throws {
    let project = try TemporaryProject(files: [:])
    let session = session(in: project)
    let report = report(checks: [
      Violations(rule: "be final", offenders: [], checkedCount: Int.max - 1),
      Violations(rule: "be public", offenders: [], checkedCount: 1),
    ])

    try report.validate(in: session)
    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(
      SwiftTestingRuleReport.self, from: data
    )
    #expect(decoded.checks.map(\.checkedCount) == [Int.max - 1, 1])
    #expect(decoded.findings.violations.checkedCount == Int.max)

    try session.write(report)
    let files = try FileManager.default.contentsOfDirectory(
      at: project.rootURL, includingPropertiesForKeys: nil
    )
    try #require(files.count == 1)
    let file = try #require(files.first)
    let stored = try SwiftTestingRuleSession.readReport(at: file)
    #expect(stored.checks.map(\.checkedCount) == [Int.max - 1, 1])
    #expect(stored.findings.violations.checkedCount == Int.max)
  }

  enum PayloadChange: String, Sendable, CustomTestStringConvertible {
    case unsupportedVersion = "Unsupported version"
    case bothSnapshotForms = "Both snapshot forms"
    case neitherSnapshotForm = "Neither snapshot form"
    case missingSnapshotStore = "Snapshot IDs without store"
    case missingFix = "Missing fix slot"
    case negativeSnapshotIndex = "Negative snapshot index"
    case pastLastSnapshotIndex = "Snapshot index past last entry"
    case negativeCheckedCount = "Negative check count"
    case overflowingCheckedCount = "Check count overflow"
    case emptySessionID = "Empty session ID"
    case emptyTestID = "Empty test ID"
    case emptyRuleID = "Empty rule ID"
    case missingBaselineAcceptance = "Missing baseline acceptance"
    case extraBaselineAcceptance = "Extra baseline acceptance"

    var testDescription: String { rawValue }
  }

  private func payload(changing change: PayloadChange) throws -> Data {
    let data = try JSONEncoder().encode(sourceReport())
    var payload = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var checks = try #require(payload["checks"] as? [[String: Any]])
    var check = try #require(checks.first)
    switch change {
    case .unsupportedVersion:
      payload["version"] = 99
    case .bothSnapshotForms:
      payload["snapshotIDs"] = [String]()
    case .neitherSnapshotForm:
      payload.removeValue(forKey: "snapshots")
    case .missingSnapshotStore:
      payload.removeValue(forKey: "snapshots")
      payload["snapshotIDs"] = [String]()
    case .missingFix:
      check["fixes"] = [Any]()
    case .negativeSnapshotIndex, .pastLastSnapshotIndex:
      var fixes = try #require(check["fixes"] as? [[String: Any]])
      var fix = try #require(fixes.first)
      var edits = try #require(fix["edits"] as? [[String: Any]])
      var edit = try #require(edits.first)
      edit["snapshot"] = change == .negativeSnapshotIndex ? -1 : 1
      edits[0] = edit
      fix["edits"] = edits
      fixes[0] = fix
      check["fixes"] = fixes
    case .negativeCheckedCount:
      check["checkedCount"] = -1
    case .overflowingCheckedCount:
      checks.append(check)
      check["checkedCount"] = Int.max
      payload["baselineAccepted"] = [false, false]
    case .emptySessionID:
      payload["sessionID"] = ""
    case .emptyTestID:
      payload["testID"] = ""
    case .emptyRuleID:
      payload["ruleID"] = ""
    case .missingBaselineAcceptance:
      payload["baselineAccepted"] = [Bool]()
    case .extraBaselineAcceptance:
      payload["baselineAccepted"] = [false, false]
    }
    checks[0] = check
    payload["checks"] = checks
    return try JSONSerialization.data(withJSONObject: payload)
  }

  private func sourceReport(baselineAccepted: [Bool] = [false]) throws
    -> SwiftTestingRuleReport
  {
    let snapshot = SourceSnapshot(
      filePath: "/project/Screen.swift", text: "class Screen {}",
      swiftLanguageMode: .v6
    )
    let slice = try SourceSlice(snapshot: snapshot, range: 0..<0)
    let offender = Offender(
      description: "class Screen", name: "Screen",
      location: .init(filePath: snapshot.filePath, line: 1, column: 1)
    )
    return report(checks: [Violations(
      rule: "be final", offenders: [offender], checkedCount: 1,
      witnesses: [nil],
      fixes: [SourceFix("Add final", edits: [
        slice.replacement(with: "final "),
      ])]
    )], baselineAccepted: baselineAccepted)
  }

  private func report(
    sessionID: String = "run", testID: String = "test",
    ruleID: Rule.ID = "rule",
    checks: [Violations<Offender>] = [], baselineAccepted: [Bool] = []
  ) -> SwiftTestingRuleReport {
    SwiftTestingRuleReport(
      sessionID: sessionID, testID: testID, ruleID: ruleID,
      name: "Classes are final", enforcement: .enforced, hint: nil,
      location: .init(filePath: "/project/Rules.swift", line: 1, column: 1),
      findings: Rule.Findings(checks: checks, warnings: []),
      baselineAccepted: baselineAccepted, origin: nil
    )
  }

  private func session(in project: TemporaryProject, id: String = "run")
    -> SwiftTestingRuleSession
  {
    SwiftTestingRuleSession(
      id: id, directory: project.rootURL.path, rootPath: project.rootURL.path
    )
  }
}
