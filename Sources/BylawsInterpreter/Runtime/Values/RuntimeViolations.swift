import BylawsCore
import BylawsSemantics

struct RuntimeViolations: Sendable, Equatable {
  let rule: String
  let offenders: [RuntimeModelValue]
  let checkedCount: Int
  let witnesses: [DeclarationLocation?]

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.rule == rhs.rule && lhs.offenders == rhs.offenders
      && lhs.checkedCount == rhs.checkedCount
  }

  init(
    rule: String,
    offenders: [RuntimeModelValue],
    checkedCount: Int,
    witnesses: [DeclarationLocation?]? = nil
  ) {
    self.rule = rule
    self.offenders = offenders
    self.checkedCount = checkedCount
    self.witnesses = witnesses
      ?? Array(repeating: nil, count: offenders.count)
  }

  var erased: Violations<Offender> {
    Violations(
      rule: rule,
      offenders: zip(offenders, witnesses).compactMap { value, witness in
        guard let offender = value.offender else { return nil }
        guard let witness else { return offender }
        return Offender(
          description: offender.description,
          name: offender.name,
          location: witness,
          affectedPath: offender.affectedPath,
          requirement: offender.requirement
        )
      },
      checkedCount: checkedCount
    )
  }
}
