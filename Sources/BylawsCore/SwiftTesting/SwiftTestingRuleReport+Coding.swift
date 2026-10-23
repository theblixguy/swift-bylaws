import BylawsSemantics
import Foundation

extension SwiftTestingRuleReport: Codable {
  package init(from decoder: any Decoder) throws {
    let payload = try Payload(from: decoder)
    guard payload.version == SwiftTestingRuleSession.protocolVersion else {
      throw SwiftTestingRuleSessionError.unsupportedVersion(payload.version)
    }
    let snapshots: [SourceSnapshot]
    switch (payload.snapshots, payload.snapshotIDs) {
    case let (.some(values), .none): snapshots = values
    case let (.none, .some(ids)):
      guard let store = decoder.userInfo[SwiftTestingSnapshotStore.codingKey]
        as? SwiftTestingSnapshotStore
      else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "The report decoder must have a source snapshot store"
        )
      }
      snapshots = try ids.map(store.read)
    default:
      throw SwiftTestingRuleSessionError.malformedReport(
        "The report must contain either source snapshots or snapshot IDs"
      )
    }
    self.init(
      sessionID: payload.sessionID, testID: payload.testID,
      ruleID: payload.ruleID, name: payload.name,
      enforcement: payload.enforcement, hint: payload.hint,
      location: payload.location,
      findings: Rule.Findings(
        checks: try payload.checks.map { try $0.decoded(snapshots: snapshots) },
        warnings: payload.warnings
      ),
      baselineAccepted: payload.baselineAccepted, origin: payload.origin
    )
    try validateContents()
  }

  package func encode(to encoder: any Encoder) throws {
    try validateContents()
    var snapshots: [SourceSnapshot] = []
    var indices: [SourceSnapshot: Int] = [:]
    let checks = checks.map { check in
      Check(
        rule: check.rule, offenders: check.offenders,
        checkedCount: check.checkedCount,
        fixes: check.fixes.map { fix in
          fix.map { fix in
            Fix(title: fix.title, edits: fix.edits.map { edit in
              let snapshot = edit.source.snapshot
              let index: Int
              if let existing = indices[snapshot] { index = existing }
              else {
                index = snapshots.count
                snapshots.append(snapshot)
                indices[snapshot] = index
              }
              return Edit(
                snapshot: index, range: edit.source.range,
                replacement: edit.replacement
              )
            })
          }
        }
      )
    }
    let store = encoder.userInfo[SwiftTestingSnapshotStore.codingKey]
      as? SwiftTestingSnapshotStore
    try Payload(
      version: version, sessionID: sessionID, testID: testID,
      ruleID: ruleID, name: name, enforcement: enforcement, hint: hint,
      location: location, checks: checks, warnings: warnings,
      baselineAccepted: baselineAccepted, origin: origin,
      snapshots: store == nil ? snapshots : nil,
      snapshotIDs: try store.map { try snapshots.map($0.write) }
    ).encode(to: encoder)
  }

  private struct Payload: Codable {
    let version: Int
    let sessionID: String
    let testID: String
    let ruleID: Rule.ID
    let name: String
    let enforcement: Enforcement
    let hint: String?
    let location: DeclarationLocation
    let checks: [Check]
    let warnings: [Rule.Warning]
    let baselineAccepted: [Bool]
    let origin: Rule.Origin?
    let snapshots: [SourceSnapshot]?
    let snapshotIDs: [String]?
  }

  private struct Check: Codable {
    let rule: String
    let offenders: [Offender]
    let checkedCount: Int
    let fixes: [Fix?]

    func decoded(snapshots: [SourceSnapshot]) throws -> Violations<Offender> {
      guard fixes.count == offenders.count else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "The fix count must equal the offender count"
        )
      }
      return try Violations(
        rule: rule, offenders: offenders, checkedCount: checkedCount,
        witnesses: Array(repeating: nil, count: offenders.count),
        fixes: fixes.map { fix in
          try fix.map { fix in
            try SourceFix(fix.title, edits: fix.edits.map { edit in
              guard snapshots.indices.contains(edit.snapshot) else {
                throw SwiftTestingRuleSessionError.malformedReport(
                  "Source snapshot index \(edit.snapshot) is outside the report's snapshot list"
                )
              }
              return try SourceFix.Edit(
                source: SourceSlice(
                  snapshot: snapshots[edit.snapshot], range: edit.range
                ), replacement: edit.replacement
              )
            })
          }
        }
      )
    }
  }

  private struct Fix: Codable {
    let title: String?
    let edits: [Edit]
  }

  private struct Edit: Codable {
    let snapshot: Int
    let range: Range<Int>
    let replacement: String
  }
}
