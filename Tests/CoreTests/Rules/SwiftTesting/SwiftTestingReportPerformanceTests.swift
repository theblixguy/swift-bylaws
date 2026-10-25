import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite(
  "Swift Testing report performance",
  .enabled(if: ProcessInfo.processInfo.environment["BYLAWS_PERF"] != nil)
)
struct SwiftTestingReportPerformanceTests {
  @Test(
    "Compact report encodes and decodes one source file",
    .serialized,
    arguments: [100, 1000]
  )
  func compactTransport(fixCount: Int) throws {
    let report = try report(fixCount: fixCount)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let clock = ContinuousClock()
    var data = Data()
    var restored: SwiftTestingRuleReport?

    let encoding = try clock.measure { data = try encoder.encode(report) }
    let decoding = try clock.measure {
      restored = try decoder.decode(SwiftTestingRuleReport.self, from: data)
    }

    let decoded = try #require(restored)
    let check = try #require(decoded.checks.first)
    let first = try #require(check.fixes.first ?? nil)
    let last = try #require(check.fixes.last ?? nil)
    let payload = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect((payload["snapshots"] as? [Any])?.count == 1)
    #expect(check.checkedCount == fixCount * 2)
    #expect(check.offenders.count == fixCount)
    #expect(check.fixes.count == fixCount)
    #expect(check.fixes.compactMap(\.self)
      .reduce(0) { $0 + $1.edits.count } == fixCount)
    #expect(check.fixes.compactMap(\.self).reduce(0) {
      $0 + $1.layoutCandidates.count
    } == fixCount)
    #expect(first.edits.map(\.replacement) == ["@Observable @MainActor\n"])
    #expect(last.edits.map(\.replacement) == ["\n@Observable @MainActor\n"])
    #expect(first.layoutCandidates
      .map(\.source.text) == ["\n@Observable @MainActor\n"])
    #expect(last.layoutCandidates
      .map(\.replacement) == ["\n@Observable @MainActor\n"])
    #expect(decoded.checks == report.checks)
    print(
      "[perf] compact report \(fixCount) fixes, \(fixCount) layout candidates, \(data.count) bytes, encode \(encoding), decode \(decoding)"
    )
  }

  private func report(fixCount: Int) throws -> SwiftTestingRuleReport {
    let source = (0..<fixCount).map { index in
      "@MainActor\n@Observable class Changed\(index) {}\n"
        + "@Observable @MainActor\nclass Kept\(index) {}\n"
    }.joined()
    let file = try FileCollector.collect(
      source: source,
      path: "/project/Screens.swift"
    )
    var offenders: [Offender] = []
    var fixes: [SourceFix?] = []
    var pending: SourceFix.Edit?
    for declaration in file.classes {
      let attributes = declaration.attributes
      let edit = try attributes.replacement {
        Line {
          attributes.sorted { lhs, rhs in
            lhs.name == "Observable" && rhs.name != "Observable"
          }
        }
      }
      if declaration.name.hasPrefix("Changed") {
        pending = edit
        offenders.append(Offender(
          description: declaration.name, name: declaration.name,
          location: declaration.location
        ))
      } else {
        let changed = try #require(pending)
        fixes.append(SourceFix(edits: [changed], layoutCandidates: [edit]))
        pending = nil
      }
    }
    try #require(fixes.count == fixCount)
    return SwiftTestingRuleReport(
      sessionID: "run", testID: "test", ruleID: "attributes",
      name: "Order attributes", enforcement: .enforced, hint: nil,
      location: .start(of: "/project/Rules.swift"),
      findings: Rule.Findings(checks: [Violations(
        rule: "Order attributes", offenders: offenders,
        checkedCount: fixCount * 2,
        witnesses: Array(repeating: nil, count: fixCount), fixes: fixes
      )]),
      baselineAccepted: Array(repeating: false, count: fixCount), origin: nil
    )
  }
}
