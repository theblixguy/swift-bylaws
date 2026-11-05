extension SupportedAPI {
  static let correctionOutcomeRuntimeMembers: [RuntimeMemberAPI] = [
    property(
      .correction,
      on: [
        .sourceCorrection,
        .layoutCorrection,
        .sourceFix,
        .sourceEdit,
        .array,
      ],
      result: .fixed(.sourceCorrection)
    ),
    property(
      .outcome,
      on: [.sourceCorrection],
      result: .fixed(.staticMember([.sourceCorrectionOutcome]))
    ),
    property(
      .reason,
      on: [.sourceCorrection],
      result: .fixed(.optional(.string))
    ),
    property(
      .fix,
      on: [.sourceCorrection],
      result: .fixed(.optional(.sourceFix))
    ),
    property(.edits, on: [.sourceFix], result: .fixed(.array(.sourceEdit))),
    property(.title, on: [.sourceFix], result: .fixed(.optional(.string))),
    property(
      .notApplicable,
      on: [.staticType("SourceCorrection")],
      result: .fixed(.sourceCorrection)
    ),
    property(
      .satisfied,
      on: [.staticType("SourceCorrection")],
      result: .fixed(.sourceCorrection)
    ),
    property(
      .outcomeType,
      on: [.staticType("SourceCorrection")],
      result: .fixed(.staticType("SourceCorrection.Outcome"))
    ),
    method(
      .unavailable,
      on: [.staticType("SourceCorrection")],
      arguments: .exact([.init(nil, .exact(.string))]),
      result: .fixed(.sourceCorrection)
    ),
    method(
      .undetermined,
      on: [.staticType("SourceCorrection")],
      arguments: .exact([.init(nil, .exact(.string))]),
      result: .fixed(.sourceCorrection)
    ),
    method(
      .preparedFix,
      on: [.sourceCorrection],
      arguments: .exact([]),
      result: .fixed(.optional(.sourceFix)),
      canThrow: true
    ),
  ]
}
