import BylawsCore
import BylawsSemantics
import Testing
@testable import BylawsInterpreter

@Suite("Portable correction storage")
struct RuntimeCorrectionStorageTests {
  @Test("Builder fix expressions match native title behaviour")
  func fixTitles() throws {
    let file = try FileCollector.collect(
      source: "class Model {}",
      path: "/virtual/Model.swift"
    )
    let edit = try file.classes.only().nameSource.replacement(with: "Changed")
    let fix = SourceFix("Rename", edits: [edit])
    let expression = try RuntimeBuilder.correction.combine(
      [.sourceFix(fix)],
      at: .start(of: "Rules.swift")
    )
    .correction(at: .start(of: "Rules.swift"))
    let returned = try RuntimeValue.sourceFix(fix)
      .correction(at: .start(of: "Rules.swift"))
    let value = try RuntimeBuilder.correction.combine(
      [.sourceCorrection(SourceCorrection(fix))],
      at: .start(of: "Rules.swift")
    )
    .correction(at: .start(of: "Rules.swift"))

    #expect(expression.fix?.title == "Rename")
    #expect(returned.fix?.title == "Rename")
    #expect(value.fix?.title == "Rename")
    #expect(expression.fix?.edits == [edit])
  }

  @Test("Absent and all-nil corrections stay absent through erasure")
  func noCorrections() {
    let offenders = ["first", "second"].map {
      RuntimeModelValue.offender(Offender(
        description: $0, location: .start(of: "/virtual/App.swift")
      ))
    }
    let absent = RuntimeViolations(
      rule: "be final",
      offenders: offenders,
      checkedCount: 2
    )
    let explicit = RuntimeViolations(
      rule: "be final", offenders: offenders, checkedCount: 2,
      fixes: [nil, nil]
    )

    #expect(absent.proposedFixes == nil)
    #expect(explicit.proposedFixes == nil)
    #expect(absent == explicit)
    #expect(absent.erased.proposedFixes == nil)
    #expect(absent.erased.fixes == [nil, nil])
    #expect(absent.erased.offenders.map(\.description) == ["first", "second"])
  }

  @Test("Erasure keeps mixed corrections aligned with reportable offenders")
  func mixedCorrections() throws {
    let file = try FileCollector.collect(
      source: "class Old {}",
      path: "/virtual/App.swift"
    )
    let fix =
      try SourceFix(edits: [file.classes.only().nameSource
          .replacement(with: "New")])
    let first = Offender(
      description: "first",
      location: .start(of: "/virtual/App.swift")
    )
    let last = Offender(
      description: "last",
      location: .start(of: "/virtual/App.swift")
    )
    let value = RuntimeViolations(
      rule: "use name", offenders: [
        .offender(first), .attribute(Attribute(name: "MainActor")),
        .offender(last),
      ],
      checkedCount: 3, fixes: [nil, SourceFix("Skip", edits: []), fix]
    )
    let result = value.erased

    #expect(result.offenders.map(\.description) == ["first", "last"])
    #expect(result.checkedCount == 3)
    #expect(result.fixes == [nil, fix])
    #expect(result.fixes[1]?.edits.first?.replacement == "New")
    #expect(value.removingCorrections().proposedFixes == nil)
  }
}
