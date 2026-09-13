extension SupportedAPI {
  static let resultRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .checks,
      on: [.findings],
      result: .fixed(.array(.violations(.offender)))
    ),
    property(
      .requirement,
      on: [.model(.offender)],
      result: .fixed(.optional(.string))
    ),
    property(
      .violations,
      on: [.findings],
      result: .fixed(.violations(.offender))
    ),
    property(
      .warnings,
      on: [.findings],
      result: .fixed(.array(.model(.ruleWarning)))
    ),
    property(
      .requirementDescription,
      on: [.matcher],
      result: .fixed(.string)
    ),
    property(.count, on: [.violations], result: .fixed(.integer)),
    property(
      .isEmpty,
      on: [.violations],
      result: .fixed(.boolean)
    ),
    property(.rule, on: [.violations], result: .fixed(.string)),
    property(
      .checkedCount,
      on: [.violations],
      result: .fixed(.integer)
    ),
    property(
      .offenders,
      on: [.violations],
      result: .violationOffenders
    ),
    property(
      .description,
      on: [.model(.offender)],
      result: .fixed(.string)
    ),
    property(
      .name,
      on: [.model(.offender)],
      result: .fixed(.optional(.string))
    ),
    property(.path, on: [.model(.offender)], result: .fixed(.string)),
    property(
      .affectedPath,
      on: [.model(.offender)],
      result: .fixed(.optional(.string))
    ),
    property(.line, on: [.model(.offender)], result: .fixed(.integer)),
  ]

  static let rangeRuntimeMembers: [RuntimeMemberAPI] = [
    property(.count, on: [.integerRange], result: .fixed(.integer)),
    property(.isEmpty, on: [.integerRange], result: .fixed(.boolean)),
    property(.lowerBound, on: [.integerRange], result: .fixed(.integer)),
    property(.upperBound, on: [.integerRange], result: .fixed(.integer)),
    method(
      .contains,
      on: [.integerRange],
      arguments: .exact([.init(nil, .exact(.integer))]),
      result: .fixed(.boolean)
    ),
  ]
}
