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

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rule == rhs.rule && lhs.offenders == rhs.offenders
      && lhs.checkedCount == rhs.checkedCount
      && lhs.proposedFixes == rhs.proposedFixes
      && lhs.layoutCandidates == rhs.layoutCandidates
  }

  init(
    rule: String,
    offenders: [RuntimeModelValue],
    checkedCount: Int,
    witnesses: [DeclarationLocation?]? = nil,
    fixes: [SourceFix?]? = nil,
    codebase: Codebase? = nil,
    layoutCandidates: [SourceFix.Edit] = []
  ) {
    self.rule = rule
    self.offenders = offenders
    self.checkedCount = checkedCount
    self.codebase = codebase
    self.layoutCandidates = layoutCandidates
    precondition(fixes == nil || fixes?.count == offenders.count)
    proposedFixes = fixes
      .flatMap { $0.contains(where: { $0 != nil }) ? $0 : nil }
    self.witnesses = witnesses
      ?? Array(repeating: nil, count: offenders.count)
  }

  var erased: Violations<Offender> {
    var retained: [Offender] = []
    var retainedFixes: [SourceFix?]? = proposedFixes.map { _ in [] }
    for index in offenders.indices {
      guard let offender = offenders[index].offender else { continue }
      if let witness = witnesses[index] {
        retained.append(Offender(
          description: offender.description,
          name: offender.name,
          location: witness,
          affectedPath: offender.affectedPath,
          requirement: offender.requirement
        ))
      } else {
        retained.append(offender)
      }
      if let proposedFixes { retainedFixes?.append(proposedFixes[index]) }
    }
    return Violations(
      rule: rule,
      offenders: retained,
      checkedCount: checkedCount,
      witnesses: Array(repeating: nil, count: retained.count),
      fixes: retainedFixes,
      codebase: codebase,
      layoutCandidates: layoutCandidates
    )
  }
}
