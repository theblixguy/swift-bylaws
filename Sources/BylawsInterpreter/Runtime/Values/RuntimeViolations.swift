import BylawsCore
import BylawsSemantics

struct RuntimeViolations: Sendable, Equatable {
  let rule: String
  let offenders: [RuntimeModelValue]
  let checkedCount: Int
  let witnesses: [DeclarationLocation?]
  let fixes: [SourceFix?]
  let codebase: Codebase?

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rule == rhs.rule && lhs.offenders == rhs.offenders
      && lhs.checkedCount == rhs.checkedCount && lhs.fixes == rhs.fixes
  }

  init(
    rule: String,
    offenders: [RuntimeModelValue],
    checkedCount: Int,
    witnesses: [DeclarationLocation?]? = nil,
    fixes: [SourceFix?]? = nil,
    codebase: Codebase? = nil
  ) {
    self.rule = rule
    self.offenders = offenders
    self.checkedCount = checkedCount
    self.codebase = codebase
    self.fixes = fixes ?? Array(repeating: nil, count: offenders.count)
    self.witnesses = witnesses
      ?? Array(repeating: nil, count: offenders.count)
  }

  var erased: Violations<Offender> {
    var retained: [Offender] = []
    var retainedFixes: [SourceFix?] = []
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
      retainedFixes.append(fixes[index])
    }
    return Violations(
      rule: rule,
      offenders: retained,
      checkedCount: checkedCount,
      witnesses: Array(repeating: nil, count: retained.count),
      fixes: retainedFixes,
      codebase: codebase
    )
  }
}
