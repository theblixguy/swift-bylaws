import BylawsCore
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Source list correction plans")
struct SourceListCorrectionPlanTests {
  @Test(
    "Apply declaration insertions from one or separate fixes",
    arguments: [false, true]
  )
  func declarationInsertions(separateFixes: Bool) async throws {
    let project = try TemporaryProject(files: ["Store.swift": "class Store {}"])
    let file = try FileCollector
      .collect(fileAt: project.fileURL(for: "Store.swift").path)
    let declaration = try #require(file.classes.first)
    let operations = [
      try Insert("@MainActor", into: declaration.attributeList).correction,
      try Insert("final", into: declaration.modifierList).correction,
    ]
    let corrections = separateFixes ? operations :
      [SourceCorrection(combining: operations)]
    let plan = CorrectionPlan.prepare(
      reports: try corrections.enumerated().map { index, correction in
        try report(
          correction,
          id: "declaration-\(index)",
          location: declaration.location
        )
      }, rootPath: project.rootURL.path
    )

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == (separateFixes ? 2 : 1))
    _ = try await plan.apply(captures: [])
    #expect(try String(
      contentsOf: project.fileURL(for: "Store.swift"),
      encoding: .utf8
    )
      == "@MainActor final class Store {}")
  }

  @Test(
    "Insertion activates passing width layout from one or separate reports",
    arguments: [false, true]
  )
  func lengthThreshold(separateReports: Bool) async throws {
    let project = try TemporaryProject(files: ["Call.swift": "send(1, 2)"])
    let file = try FileCollector
      .collect(fileAt: project.fileURL(for: "Call.swift").path)
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first)
    let list = try call.argumentList
    let layout = try Layout(list, when: !.maximumLineLength(...12)) {
      Newline()
      Lines { list }
      Newline()
    }.correction
    #expect(layout.outcome == .satisfied)
    let insertion = try Insert("longValue", into: list).correction
    let reports = if separateReports {
      [
        RuleReport(
          id: "layout", name: "Wrap long calls", enforcement: .enforced,
          hint: nil, location: call.location,
          violations: Violations<Offender>(
            rule: "Wrap long calls", offenders: [], checkedCount: 1,
            witnesses: [],
            layoutCandidates: try #require(layout.fix).layoutCandidates
          ), warnings: []
        ),
        try report(insertion, id: "insert", location: call.location),
      ]
    } else {
      [try report(
        SourceCorrection(combining: [layout, insertion]),
        id: "call", location: call.location
      )]
    }
    let plan = CorrectionPlan.prepare(
      reports: reports, rootPath: project.rootURL.path
    )
    let expected = Data("send(\n  1,\n  2,\n  longValue\n)".utf8)

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.replacement == expected)

    let paths = try await plan.apply(captures: [])

    #expect(paths == [file.path])
    #expect(try Data(contentsOf: project.fileURL(for: "Call.swift")) ==
      expected)
  }

  private func report(
    _ correction: SourceCorrection, id: String, location: DeclarationLocation
  ) throws -> RuleReport {
    let fix = try #require(correction.fix)
    return RuleReport(
      id: Rule.ID(id), name: "Correct source list", enforcement: .enforced,
      hint: nil, location: location,
      violations: Violations(
        rule: "Correct source list", offenders: [Offender(
          description: "source",
          location: location
        )],
        checkedCount: 1, witnesses: [nil], fixes: [fix]
      ), warnings: []
    )
  }
}
