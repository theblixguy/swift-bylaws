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

  enum OwnerRejection: CaseIterable {
    case reportScope, conflict, parseFailure
  }

  @Test(
    "Rejected fix releases its layout context",
    arguments: OwnerRejection.allCases, [false, true]
  )
  func rejectedOwner(
    reason: OwnerRejection, candidateInEdits: Bool
  ) async throws {
    let original = "let value = send(1, 2)\n"
    let project = try TemporaryProject(files: [
      "Value.swift": original,
      "Owner.swift": "let marker = 0\n",
      "Excluded.swift": "let other = 0\n",
    ])
    let file = try FileCollector
      .collect(fileAt: project.fileURL(for: "Value.swift").path)
    let owner = try FileCollector
      .collect(fileAt: project.fileURL(for: "Owner.swift").path)
    let call = try #require(file.calls.first)
    let candidate = try call.arguments.replacement(whenLineExceeds: 22) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    try #require(candidate.source.text == candidate.replacement)
    let ownerValue = try #require(owner.syntaxNodes(of: .integerLiteral).first)
    let ownerEdit = if reason == .parseFailure {
      try owner.source.replacement(with: "let marker = {\n")
    } else {
      try ownerValue.source.replacement(with: "1")
    }
    var ownerEdits = [ownerEdit]
    if reason == .reportScope {
      let excluded = try FileCollector
        .collect(fileAt: project.fileURL(for: "Excluded.swift").path)
      ownerEdits.append(try excluded.source
        .replacement(with: "let other = 1\n"))
    }
    let ownerFix = SourceFix(
      edits: ownerEdits + (candidateInEdits ? [candidate] : []),
      layoutCandidates: candidateInEdits ? [] : [candidate]
    )
    var fixes = [ownerFix]
    var offenders = [Offender(
      description: "owner", location: ownerValue.location
    )]
    if reason == .conflict {
      fixes.append(SourceFix(edits: [try ownerValue.source
          .replacement(with: "2")]))
      offenders.append(Offender(
        description: "competing owner", location: ownerValue.location
      ))
    }
    let owners = Violations(
      rule: "Change owner", offenders: offenders,
      checkedCount: offenders.count,
      witnesses: Array(repeating: nil, count: offenders.count),
      fixes: fixes.map(Optional.some)
    )
    let first = try #require(call.arguments.first)
    let child = try first.expressionSource.replacement(with: "longValue")
    let changed = Violations(
      rule: "Use named value",
      offenders: [Offender(description: "value", location: call.location)],
      checkedCount: 1, witnesses: [nil], fixes: [SourceFix(edits: [child])]
    )

    let plan = CorrectionPlan.prepare(
      reports: [report(id: "owner", check: owners),
                report(id: "value", check: changed)],
      rootPath: project.rootURL.path,
      reportPaths: ["Value.swift", "Owner.swift"]
    )

    #expect(plan.diagnostics.count == (reason == .conflict ? 2 : 1))
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.path == file.path)
    #expect(plan.changes.first?.replacement
      == Data("let value = send(longValue, 2)\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data(original.utf8))

    let paths = try await plan.apply(captures: [])

    #expect(paths == [file.path])
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data("let value = send(longValue, 2)\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Owner.swift"))
      == Data("let marker = 0\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Excluded.swift"))
      == Data("let other = 0\n".utf8))
  }

  @Test("Line-end insertions retain physical-line layout scope", arguments: [
    ("send(1, 2)", 10, "send(\n  1,\n  2\n).id"),
    ("send(1, 2)\n", 10, "send(\n  1,\n  2\n).id\n"),
    ("send(1, 2)\r\n", 10, "send(\r\n  1,\r\n  2\r\n).id\r\n"),
    ("send(1, 2)\r", 10, "send(\r  1,\r  2\r).id\r"),
    ("send(1, 2)\n", 11, "send(1, 2)\n.id"),
    ("send(1, 2)\r\n", 12, "send(1, 2)\r\n.id"),
    ("send(1, 2)\r", 11, "send(1, 2)\r.id"),
  ])
  func lineEndInsertion(
    original: String, offset: Int, expected: String
  ) async throws {
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
    try #require(candidate.source.text == candidate.replacement)
    let insertion = try file.source.slice(offset..<offset)
      .replacement(with: ".id")
    let passing = Violations<Offender>(
      rule: "Wrap long calls", offenders: [], checkedCount: 1, witnesses: [],
      layoutCandidates: [candidate]
    )
    let changed = Violations(
      rule: "Read property",
      offenders: [Offender(description: "call", location: call.location)],
      checkedCount: 1, witnesses: [nil], fixes: [SourceFix(edits: [insertion])]
    )

    let plan = CorrectionPlan.prepare(
      reports: [report(id: "layout", check: passing),
                report(id: "property", check: changed)],
      rootPath: project.rootURL.path
    )

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.replacement == Data(expected.utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Call.swift"))
      == Data(original.utf8))

    let paths = try await plan.apply(captures: [])

    #expect(paths == [file.path])
    #expect(try Data(contentsOf: project.fileURL(for: "Call.swift"))
      == Data(expected.utf8))
  }

  @Test(
    "Public correction builder keeps layout context with its offender",
    arguments: [false, true]
  )
  func publicOwnerContext(filterOwner: Bool) async throws {
    let original = "let value = send(1, 2)\n"
    let project = try TemporaryProject(files: [
      "Value.swift": original,
      "Owner.swift": "let marker = 0\n",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["*.swift"]
    )
    let owners = try await codebase.files.named("Owner.swift")
      .violations("Change owner and format related calls") { owner in
        try owner.source.replacement(with: "let marker = 1\n")
        let related = try await codebase.files.named("Value.swift").only()
        let call = try #require(related.calls.first)
        try call.arguments.replacement(whenLineExceeds: 22) {
          for argument in call.arguments {
            Newline()
            argument
          }
          Newline()
        }
      }
    let ownerFix = try #require(owners.fixes.first ?? nil)
    #expect(owners.checkedCount == 1)
    #expect(owners.offenders.map(\.name) == ["Owner.swift"])
    #expect(owners.layoutCandidates.isEmpty)
    #expect(ownerFix.edits.count == 1)
    #expect(ownerFix.layoutCandidates.count == 1)
    #expect(ownerFix.layoutCandidates.first?.replacement == "1, 2")
    let retainedOwners = if filterOwner {
      owners.filteringOffenders { _ in false }
    } else {
      owners
    }
    let child = try await codebase.syntaxNodes(of: .integerLiteral)
      .under("Value.swift")
      .violations("Use named value") { literal in
        if literal.text == "1" {
          try literal.source.replacement(with: "longValue")
        }
      }
    #expect(child.checkedCount == 2)
    #expect(child.offenders.count == 1)

    let plan = CorrectionPlan.prepare(
      reports: [report(id: "owner", check: retainedOwners.erased()),
                report(id: "value", check: child.erased())],
      rootPath: project.rootURL.path,
      reportPaths: ["Value.swift"]
    )

    #expect(plan.diagnostics.count == (filterOwner ? 0 : 1))
    #expect(plan.fixCount == 1)
    try #require(plan.changes.count == 1)
    #expect(plan.changes.first?.replacement
      == Data("let value = send(longValue, 2)\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data(original.utf8))

    let paths = try await plan.apply(captures: [])

    #expect(paths == [project.fileURL(for: "Value.swift").path])
    #expect(try Data(contentsOf: project.fileURL(for: "Value.swift"))
      == Data("let value = send(longValue, 2)\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: "Owner.swift"))
      == Data("let marker = 0\n".utf8))
  }

  private func report(id: Rule.ID, check: Violations<Offender>) -> RuleReport {
    RuleReport(
      id: id, name: "Format source", enforcement: .enforced, hint: nil,
      location: .start(of: "/Bylaws.swift"), violations: check, warnings: []
    )
  }
}
