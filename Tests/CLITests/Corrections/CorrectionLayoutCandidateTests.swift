import BylawsCore
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction layout context")
struct CorrectionLayoutCandidateTests {
  @Test(
    "Child growth activates passing layout during preparation and application"
  )
  func activation() async throws {
    let original = "let value = send(1, 2)\n"
    let expected = "let value = send(\n  longValue,\n  2\n)\n"
    let project = try TemporaryProject(files: ["Value.swift": original])
    let file = try FileCollector
      .collect(fileAt: project.fileURL(for: "Value.swift").path)
    let call = try #require(file.calls.first)
    let candidate = try call.arguments.replacement(whenLineExceeds: 22) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    try #require(candidate.source.text == candidate.replacement)
    let first = try #require(call.arguments.first)
    let child = try first.expressionSource.replacement(with: "longValue")
    let passing = Violations<Offender>(
      rule: "Wrap long calls", offenders: [], checkedCount: 1, witnesses: [],
      layoutCandidates: [candidate]
    )
    let changed = Violations(
      rule: "Use named value",
      offenders: [Offender(
        description: "first argument",
        location: call.location
      )],
      checkedCount: 1, witnesses: [nil], fixes: [SourceFix(edits: [child])]
    )
    let plan = CorrectionPlan.prepare(
      reports: [
        report(id: "layout", check: passing),
        report(id: "value", check: changed),
      ],
      rootPath: project.rootURL.path
    )

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.replacement == Data(expected.utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data(original.utf8))

    let paths = try await plan.apply(captures: [])

    #expect(paths == [file.path])
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data(expected.utf8))
  }

  @Test("Callee growth activates same-line layout during application")
  func calleeGrowth() async throws {
    let original = "send(1, 2)\n"
    let expected = "sendWithLongName(\n  1,\n  2\n)\n"
    let project = try TemporaryProject(files: ["Call.swift": original])
    let file = try FileCollector
      .collect(fileAt: project.fileURL(for: "Call.swift").path)
    let node = try #require(file.syntaxNodes(of: .functionCall).first)
    let call = try #require(node.call)
    let candidate = try call.arguments.replacement(whenLineExceeds: 10) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    try #require(candidate.source.text.utf8
      .elementsEqual(candidate.replacement.utf8))
    let active = try call.memberNameSource.replacement(with: "sendWithLongName")
    let passing = Violations<Offender>(
      rule: "Wrap long calls", offenders: [], checkedCount: 1, witnesses: [],
      layoutCandidates: [candidate]
    )
    let changed = Violations(
      rule: "Use current call name",
      offenders: [Offender(description: "call", location: call.location)],
      checkedCount: 1, witnesses: [nil], fixes: [SourceFix(edits: [active])]
    )

    let plan = CorrectionPlan.prepare(
      reports: [
        report(id: "layout", check: passing),
        report(id: "callee", check: changed),
      ],
      rootPath: project.rootURL.path
    )

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.replacement == Data(expected.utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Call.swift")) ==
      Data(original.utf8))
    let paths = try await plan.apply(captures: [])
    #expect(paths == [file.path])
    #expect(try Data(contentsOf: project.fileURL(for: "Call.swift")) ==
      Data(expected.utf8))
  }

  private func report(id: Rule.ID, check: Violations<Offender>) -> RuleReport {
    RuleReport(
      id: id, name: "Format source", enforcement: .enforced, hint: nil,
      location: .start(of: "/Bylaws.swift"), violations: check, warnings: []
    )
  }
}
