import BylawsCore
import BylawsSemantics

struct RuntimeViolations: Sendable, Equatable {
  let rule: String
  let offenders: [RuntimeModelValue]
  let checkedCount: Int
  let witnesses: [DeclarationLocation?]
  let proposedFixes: [SourceFix?]?
  let codebase: Codebase?
  let layoutCandidates: [SourceFix.Edit]
  let correctionFailures: [String?]?

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rule == rhs.rule && lhs.offenders == rhs.offenders
      && lhs.checkedCount == rhs.checkedCount
      && lhs.proposedFixes == rhs.proposedFixes
      && lhs.layoutCandidates == rhs.layoutCandidates
      && lhs.correctionFailures == rhs.correctionFailures
  }

  init(
    rule: String,
    offenders: [RuntimeModelValue],
    checkedCount: Int,
    witnesses: [DeclarationLocation?]? = nil,
    fixes: [SourceFix?]? = nil,
    codebase: Codebase? = nil,
    layoutCandidates: [SourceFix.Edit] = [],
    correctionFailures: [String?]? = nil
  ) {
    self.rule = rule
    self.offenders = offenders
    self.checkedCount = checkedCount
    self.codebase = codebase
    self.layoutCandidates = layoutCandidates
    precondition(correctionFailures == nil || correctionFailures?
      .count == offenders.count)
    self.correctionFailures = correctionFailures
      .flatMap { $0.contains { $0 != nil } ? $0 : nil }
    precondition(fixes == nil || fixes?.count == offenders.count)
    proposedFixes = fixes
      .flatMap { $0.contains(where: { $0 != nil }) ? $0 : nil }
    self.witnesses = witnesses
      ?? Array(repeating: nil, count: offenders.count)
  }

  var erased: Violations<Offender> {
    var retained: [Offender] = []
    var retainedFixes: [SourceFix?]? = proposedFixes.map { _ in [] }
    var retainedFailures: [String?]? = correctionFailures.map { _ in [] }
    for index in offenders.indices {
      guard let offender = offenders[index].offender else { continue }
      if witnesses[index] != nil || correctionFailures?[index] != nil {
        retained.append(Offender(
          description: offender.description,
          name: offender.name,
          location: witnesses[index] ?? offender.location,
          affectedPath: offender.affectedPath,
          requirement: offender.requirement,
          correctionFailure: correctionFailures?[index] ?? offender
            .correctionFailure
        ))
      } else {
        retained.append(offender)
      }
      if let proposedFixes { retainedFixes?.append(proposedFixes[index]) }
      if let correctionFailures {
        retainedFailures?.append(correctionFailures[index])
      }
    }
    return Violations(
      rule: rule,
      offenders: retained,
      checkedCount: checkedCount,
      witnesses: Array(repeating: nil, count: retained.count),
      fixes: retainedFixes,
      codebase: codebase,
      layoutCandidates: layoutCandidates,
      correctionFailures: retainedFailures
    )
  }

  func removingCorrections() -> Self {
    guard !layoutCandidates.isEmpty || proposedFixes != nil
    else { return self }
    return Self(
      rule: rule, offenders: offenders, checkedCount: checkedCount,
      witnesses: witnesses, codebase: codebase,
      correctionFailures: correctionFailures
    )
  }
}
