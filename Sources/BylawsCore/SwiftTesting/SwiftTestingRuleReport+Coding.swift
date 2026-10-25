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
    let sources = SwiftTestingReportSources(snapshots: snapshots)
    self.init(
      sessionID: payload.sessionID, testID: payload.testID,
      ruleID: payload.ruleID, name: payload.name,
      enforcement: payload.enforcement, hint: payload.hint,
      location: payload.location,
      findings: Rule.Findings(
        checks: try payload.checks.map { try $0.decoded(sources: sources) },
        warnings: payload.warnings
      ),
      baselineAccepted: payload.baselineAccepted, origin: payload.origin
    )
    try validateContents()
  }

  package func encode(to encoder: any Encoder) throws {
    try validateContents()
    let sources = SwiftTestingReportSources()
    let checks = try checks.map { try Check($0, sources: sources) }
    let store = encoder.userInfo[SwiftTestingSnapshotStore.codingKey]
      as? SwiftTestingSnapshotStore
    try Payload(
      version: version, sessionID: sessionID, testID: testID,
      ruleID: ruleID, name: name, enforcement: enforcement, hint: hint,
      location: location, checks: checks, warnings: warnings,
      baselineAccepted: baselineAccepted, origin: origin,
      snapshots: store == nil ? sources.snapshots : nil,
      snapshotIDs: try store.map { try sources.snapshots.map($0.write) }
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
    let layoutCandidates: [Edit]?

    init(
      _ check: Violations<Offender>, sources: SwiftTestingReportSources
    ) throws {
      rule = check.rule
      offenders = check.offenders
      checkedCount = check.checkedCount
      fixes = try check.fixes.map { fix in
        try fix.map { try Fix($0, sources: sources) }
      }
      layoutCandidates = try check.layoutCandidates.isEmpty ? nil
        : check.layoutCandidates.map(sources.captureCandidate)
    }

    func decoded(sources: SwiftTestingReportSources) throws
      -> Violations<Offender>
    {
      guard fixes.count == offenders.count else {
        throw SwiftTestingRuleSessionError.malformedReport(
          "The fix count must equal the offender count"
        )
      }
      return try Violations(
        rule: rule, offenders: offenders, checkedCount: checkedCount,
        witnesses: Array(repeating: nil, count: offenders.count),
        fixes: fixes.map { fix in
          try fix.map { try $0.decoded(sources: sources) }
        },
        layoutCandidates: (layoutCandidates ?? []).map(sources.restoreCandidate)
      )
    }
  }

  private struct Fix: Codable {
    let title: String?
    let edits: [Edit]
    let layoutCandidates: [Edit]?

    init(_ fix: SourceFix, sources: SwiftTestingReportSources) throws {
      title = fix.title
      edits = try fix.edits.map(sources.capture)
      layoutCandidates = try fix.layoutCandidates.isEmpty ? nil
        : fix.layoutCandidates.map(sources.captureCandidate)
    }

    func decoded(sources: SwiftTestingReportSources) throws -> SourceFix {
      try SourceFix(
        title, edits: edits.map(sources.restore),
        layoutCandidates: (layoutCandidates ?? []).map(sources.restoreCandidate)
      )
    }
  }

  private typealias Edit = SwiftTestingReportSources.Edit
}
