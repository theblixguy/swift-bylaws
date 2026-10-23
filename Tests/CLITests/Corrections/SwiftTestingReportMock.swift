import BylawsCore
import BylawsSemantics

func swiftTestingReport(
  _ result: some RuleResult, accepted: [Bool], id: Rule.ID = "final",
  origin: Rule.Origin? = nil, testID: String = "test"
) -> SwiftTestingRuleReport {
  let location = DeclarationLocation.start(of: "/project/Tests/Rules.swift")
  return SwiftTestingRuleReport(
    sessionID: "session", testID: testID, ruleID: id,
    name: "Classes are final", enforcement: .enforced, hint: nil,
    location: location, findings: result.findings(reportedAt: location),
    baselineAccepted: accepted, origin: origin
  )
}

func swiftTestingCheck(
  _ names: [String], root: String = "/virtual"
) throws -> Violations<Offender> {
  let files = try names.map { name in
    try FileCollector.collect(
      source: "class \(name) {}",
      path: root + "/\(name).swift"
    )
  }
  return try Violations(
    rule: "be final",
    offenders: zip(names, files).map { name, file in
      Offender(description: name, name: name, location: .start(of: file.path))
    },
    checkedCount: names.count,
    witnesses: Array(repeating: nil, count: names.count),
    fixes: files.map { file in
      SourceFix(
        "Add final",
        edits: [try file.source.replacement(with: "final " + file.sourceText)]
      )
    }
  )
}
