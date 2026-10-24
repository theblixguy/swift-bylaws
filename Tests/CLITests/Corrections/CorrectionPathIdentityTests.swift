import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction path identity")
struct CorrectionPathIdentityTests {
  @Test("Root aliases share conflict checks", arguments: [false, true])
  func rootAliases(conflicting: Bool) async throws {
    let project =
      try TemporaryProject(files: ["Real/Value.swift": "let value = 1"])
    let (root, physicalRoot) = try makeAlias(in: project)
    let logicalFile = try FileCollector.collect(fileAt: root
      .appendingPathComponent("Value.swift").path)
    let physicalFile = try FileCollector.collect(fileAt: physicalRoot
      .appendingPathComponent("Value.swift").path)
    let fixes = try [
      SourceFix(edits: [logicalFile.source.replacement(with: "let value = 2")]),
      SourceFix(edits: [physicalFile.source.replacement(with: conflicting
          ? "let value = 3" : "let value = 2")]),
    ]

    let plan = CorrectionPlan.prepare(
      reports: [report(fixes)], rootPath: root.path,
      reportPaths: ["Value.swift"]
    )

    if conflicting {
      #expect(plan.changes.isEmpty)
      #expect(plan.diagnostics.count == 2)
      #expect(plan.fixCount == 0)
      #expect(try Data(contentsOf: URL(fileURLWithPath: physicalFile.path))
        == Data("let value = 1".utf8))
    } else {
      #expect(plan.diagnostics.isEmpty)
      #expect(plan.changes.count == 1)
      #expect(plan.fixCount == 2)
      let changes = try await plan.apply(captures: [])
      #expect(changes == [logicalFile.path])
      #expect(try Data(contentsOf: URL(fileURLWithPath: physicalFile.path))
        == Data("let value = 2".utf8))
    }
  }

  @Test("Mixed snapshot aliases reject every proposal around nested layout")
  func mixedLayoutAliases() throws {
    let original = "let value = send(first: 1, second: 2)\nlet other = 0\n"
    let project = try TemporaryProject(files: ["Real/Value.swift": original])
    let (root, physicalRoot) = try makeAlias(in: project)
    let logicalFile = try FileCollector.collect(fileAt: root
      .appendingPathComponent("Value.swift").path)
    let physicalFile = try FileCollector.collect(fileAt: physicalRoot
      .appendingPathComponent("Value.swift").path)
    try #require(logicalFile.path != physicalFile.path)
    let call = try #require(logicalFile.calls.first)
    let argument = try #require(call.arguments.first)
    let parent = try call.arguments.replacement {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let child = try #require(try argument.labelSource)
      .replacement(with: "value")
    let disjoint = try #require(physicalFile.syntaxNodes(of: .integerLiteral)
      .last)
      .source.replacement(with: "4")
    let nestedFixes = [SourceFix(edits: [parent]), SourceFix(edits: [child])]
    let aliasFix = SourceFix(edits: [disjoint])
    let nestedControl = CorrectionPlan.prepare(
      reports: [report(nestedFixes)], rootPath: root.path
    )
    let aliasControl = CorrectionPlan.prepare(
      reports: [report([aliasFix])], rootPath: root.path
    )
    try #require(nestedControl.diagnostics.isEmpty)
    try #require(nestedControl.fixCount == 2)
    let nestedChange = try #require(nestedControl.changes.first)
    #expect(nestedChange.replacement == Data("""
    let value = send(
      value: 1,
      second: 2
    )
    let other = 0

    """.utf8))
    try #require(aliasControl.diagnostics.isEmpty)
    try #require(aliasControl.fixCount == 1)
    try #require(aliasControl.changes.count == 1)

    let plan = CorrectionPlan.prepare(
      reports: [report(nestedFixes + [aliasFix])], rootPath: root.path
    )

    #expect(plan.changes.isEmpty)
    #expect(plan.fixCount == 0)
    #expect(plan.diagnostics.count == 3)
    #expect(try Data(contentsOf: URL(fileURLWithPath: physicalFile.path))
      == Data(original.utf8))
  }

  @Test(
    "Dormant layout from alias cannot be omitted during preparation",
    arguments: [false, true]
  )
  func dormantLayoutAlias(additionalPhysicalEdit: Bool) throws {
    let original = "let value = send(1, 2)\n"
    let project = try TemporaryProject(files: ["Real/Value.swift": original])
    let (root, physicalRoot) = try makeAlias(in: project)
    let logicalFile = try FileCollector.collect(fileAt: root
      .appendingPathComponent("Value.swift").path)
    let physicalFile = try FileCollector.collect(fileAt: physicalRoot
      .appendingPathComponent("Value.swift").path)
    try #require(logicalFile.path != physicalFile.path)
    let physicalCall = try #require(physicalFile.calls.first)
    let candidate = try physicalCall.arguments
      .replacement(whenLineExceeds: 22) {
        for argument in physicalCall.arguments {
          Newline()
          argument
        }
        Newline()
      }
    try #require(candidate.source.text == candidate.replacement)
    let logicalCall = try #require(logicalFile.calls.first)
    let argument = try #require(logicalCall.arguments.first)
    let child = try argument.expressionSource.replacement(with: "longValue")
    var activeFixes = [SourceFix(edits: [child])]
    if additionalPhysicalEdit {
      let second = try #require(physicalCall.arguments.last)
      let edit = try second.expressionSource.replacement(with: "3")
      activeFixes.append(SourceFix(edits: [edit]))
    }
    let childReport = report(activeFixes)
    let contextReport = RuleReport(
      id: "layout", name: "Wrap long calls", enforcement: .enforced,
      hint: nil, location: .start(of: "/Bylaws.swift"),
      violations: Violations<Offender>(
        rule: "Wrap long calls", offenders: [], checkedCount: 1, witnesses: [],
        layoutCandidates: [candidate]
      ), warnings: []
    )
    let control = CorrectionPlan.prepare(
      reports: [childReport], rootPath: root.path
    )
    try #require(control.diagnostics.isEmpty)
    #expect(control.fixCount == (additionalPhysicalEdit ? 2 : 1))
    let expected = if additionalPhysicalEdit {
      "let value = send(longValue, 3)\n"
    } else {
      "let value = send(longValue, 2)\n"
    }
    #expect(control.changes.first?.replacement
      == Data(expected.utf8))

    let plan = CorrectionPlan.prepare(
      reports: [contextReport, childReport], rootPath: root.path
    )

    #expect(plan.changes.isEmpty)
    #expect(plan.fixCount == 0)
    #expect(plan.diagnostics.count == (additionalPhysicalEdit ? 2 : 1))
    for diagnostic in plan.diagnostics {
      #expect(diagnostic.message.contains("edits from one snapshot"))
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: physicalFile.path))
      == Data(original.utf8))
  }

  @Test("Physical paths retain rule protection through root alias")
  func protectedAlias() throws {
    let project =
      try TemporaryProject(files: ["Real/Policy.swift": "let value = 1"])
    let (root, physicalRoot) = try makeAlias(in: project)
    let physicalFile = try FileCollector.collect(fileAt: physicalRoot
      .appendingPathComponent("Policy.swift").path)
    let fix =
      try SourceFix(edits: [physicalFile.source
          .replacement(with: "let value = 2")])

    let plan = CorrectionPlan.prepare(
      reports: [report([fix])], rootPath: root.path,
      protectedPaths: [root.appendingPathComponent("Policy.swift").path]
    )

    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 1)
    #expect(plan.diagnostics.first?.message
      .contains("active rule or configuration") == true)
  }

  @Test("Changed root alias stops application before writes")
  func retargetedRoot() async throws {
    let original = "let value = 1"
    let project = try TemporaryProject(files: [
      "Real/Value.swift": original, "Other/Value.swift": original,
    ])
    let (root, physicalRoot) = try makeAlias(in: project)
    let file = try FileCollector.collect(fileAt: physicalRoot
      .appendingPathComponent("Value.swift").path)
    let fix =
      try SourceFix(edits: [file.source.replacement(with: "let value = 2")])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])],
      rootPath: root.path
    )
    try #require(plan.diagnostics.isEmpty)
    try #require(plan.changes.count == 1)
    try FileManager.default.removeItem(at: root)
    let other = project.rootURL.appendingPathComponent("Other")
    try FileManager.default.createSymbolicLink(
      at: root,
      withDestinationURL: other
    )

    await #expect(throws: CorrectionPlan.ApplicationError.self) {
      try await plan.apply(captures: [])
    }

    #expect(try Data(contentsOf: URL(fileURLWithPath: file.path)) ==
      Data(original.utf8))
    #expect(try Data(contentsOf: other.appendingPathComponent("Value.swift"))
      == Data(original.utf8))
  }

  private func makeAlias(in project: TemporaryProject) throws
    -> (logical: URL, physical: URL)
  {
    let root = project.rootURL.appendingPathComponent("Alias")
    let path = try #require(LexicalFilePath(project.rootURL
        .appendingPathComponent("Real").path).resolvingSymbolicLinks())
    let physicalRoot = URL(fileURLWithPath: path.string)
    try FileManager.default.createSymbolicLink(
      at: root,
      withDestinationURL: physicalRoot
    )
    return (root, physicalRoot)
  }

  private func report(_ fixes: [SourceFix]) -> RuleReport {
    let offenders = fixes.map {
      Offender(
        description: "value",
        location: .start(of: $0.edits[0].source.filePath)
      )
    }
    return RuleReport(
      id: "values", name: "Values use two", enforcement: .enforced,
      hint: nil, location: .start(of: "/Bylaws.swift"),
      violations: Violations(
        rule: "use two", offenders: offenders, checkedCount: offenders.count,
        witnesses: Array(repeating: nil, count: offenders.count),
        fixes: fixes.map(Optional.some)
      ), warnings: []
    )
  }
}
