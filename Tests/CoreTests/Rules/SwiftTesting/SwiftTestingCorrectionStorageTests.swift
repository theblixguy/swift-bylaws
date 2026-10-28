import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Swift Testing correction storage")
struct SwiftTestingCorrectionStorageTests {
  @Test("Reports omit correction fields when checks propose none")
  func omittedCorrections() throws {
    let data = try JSONEncoder().encode(report())
    let payload = try #require(JSONSerialization
      .jsonObject(with: data) as? [String: Any])
    let checks = try #require(payload["checks"] as? [[String: Any]])
    let check = try #require(checks.first)

    #expect(check["fixes"] == nil)
    #expect((payload["snapshots"] as? [Any])?.isEmpty == true)
    let restored = try JSONDecoder().decode(
      SwiftTestingRuleReport.self,
      from: data
    )
    let restoredCheck = try #require(restored.checks.first)
    #expect(restoredCheck.proposedFixes == nil)
    #expect(restoredCheck.fixes == [nil, nil])
    #expect(restoredCheck.offenders.map(\.description) == ["first", "second"])
  }

  @Test("Reports decode null and all-nil corrections", arguments: [false, true])
  func emptyCorrections(dense: Bool) throws {
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(report())
    ) as? [String: Any])
    var checks = try #require(payload["checks"] as? [[String: Any]])
    checks[0]["fixes"] = if dense {
      [NSNull(), NSNull()] as Any
    } else {
      NSNull()
    }
    payload["checks"] = checks
    let restored = try JSONDecoder().decode(
      SwiftTestingRuleReport.self,
      from: JSONSerialization.data(withJSONObject: payload)
    )
    let check = try #require(restored.checks.first)

    #expect(check.proposedFixes == nil)
    #expect(check.fixes == [nil, nil])
    #expect(check.checkedCount == 2)
  }

  @Test("Reports reject dense correction count mismatch", arguments: [0, 1, 3])
  func malformedCounts(count: Int) throws {
    var payload = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(report())
    ) as? [String: Any])
    var checks = try #require(payload["checks"] as? [[String: Any]])
    checks[0]["fixes"] = Array(repeating: NSNull(), count: count)
    payload["checks"] = checks
    let data = try JSONSerialization.data(withJSONObject: payload)

    #expect(throws: SwiftTestingRuleSessionError.malformedReport(
      "The fix count must equal the offender count"
    )) {
      try JSONDecoder().decode(SwiftTestingRuleReport.self, from: data)
    }
  }

  private func report() -> SwiftTestingRuleReport {
    let offenders = ["first", "second"].map {
      Offender(description: $0, location: .start(of: "/virtual/App.swift"))
    }
    return SwiftTestingRuleReport(
      sessionID: "run", testID: "test", ruleID: "rule",
      name: "Classes are final", enforcement: .enforced, hint: nil,
      location: .start(of: "/virtual/Rules.swift"),
      findings: Rule.Findings(violations: Violations(
        rule: "be final", offenders: offenders, checkedCount: 2
      )),
      baselineAccepted: [false, false], origin: nil
    )
  }
}
