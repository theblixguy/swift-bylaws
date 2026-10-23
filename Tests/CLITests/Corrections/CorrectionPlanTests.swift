import BylawsCore
import BylawsPaths
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Source correction plans")
struct CorrectionPlanTests {
  @Test("Correct hex letters and preserve surrounding bytes")
  func hexLetters() async throws {
    let project = try Project()
    let original = "\u{feff}// 😀\r\nlet colour = 0xdead_Beef\r\n"
    let file = try project.file("Colour.swift", text: original)
    let literal = try #require(file.syntaxNodes(of: .integerLiteral).first)
    let edits = try literal.source.matches(of: /[a-f]+/).map {
      $0.replacement(with: $0.text.uppercased())
    }
    let plan = CorrectionPlan.prepare(
      reports: [report([SourceFix(edits: edits)])], rootPath: project.root.path
    )
    #expect(plan.diagnostics.isEmpty)
    #expect(plan.changes.count == 1)
    let changed = try await plan.apply(captures: [])
    #expect(changed == [file.path])
    #expect(try Data(contentsOf: URL(fileURLWithPath: file.path))
      == Data(original.replacing("0xdead_Beef", with: "0xDEAD_BEEF").utf8))
  }

  @Test("Deduplicate equal replacements and keep both fixes")
  func equalEdits() throws {
    let project = try Project()
    let file = try project.file("Value.swift", text: "let value = 1")
    let source = try #require(file.syntaxNodes(of: .integerLiteral).first)
      .source
    let fix = SourceFix(edits: [source.replacement(with: "2")])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix, fix])],
      rootPath: project.root.path
    )
    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == 2)
    #expect(String(
      decoding: try #require(plan.changes.first).replacement,
      as: UTF8.self
    ) == "let value = 2")
  }

  @Test("Prepare many independent corrections in one file")
  func manyCorrections() throws {
    let project = try Project()
    let count = 2000
    let original = (0..<count).map { "let value\($0) = 0xaf" }
      .joined(separator: "\n")
    let file = try project.file("Values.swift", text: original)
    let fixes = try file.syntaxNodes(of: .integerLiteral).map { node in
      SourceFix(edits: [try node.source.slice(2..<4).replacement(with: "AF")])
    }

    let plan = CorrectionPlan.prepare(
      reports: [report(fixes)], rootPath: project.root.path
    )

    #expect(plan.diagnostics.isEmpty)
    #expect(plan.fixCount == count)
    #expect(plan.changes.count == 1)
    #expect(try #require(plan.changes.first).replacement
      == Data(original.replacing("0xaf", with: "0xAF").utf8))
  }

  @Test("Equal edit positions retain validation of every source snapshot")
  func staleDuplicate() throws {
    let project = try Project()
    let file = try project.file("Value.swift", text: "let value = 1")
    let stale = try FileCollector.collect(
      source: "let value = 0",
      path: file.path
    )
    let source = try #require(file.syntaxNodes(of: .integerLiteral).first)
      .source
    let staleSource = try #require(stale.syntaxNodes(of: .integerLiteral).first)
      .source
    let fix = SourceFix(edits: [
      source.replacement(with: "2"), staleSource.replacement(with: "2"),
    ])

    let plan = CorrectionPlan.prepare(
      reports: [report([fix])], rootPath: project.root.path
    )

    #expect(plan.changes.isEmpty)
    #expect(plan.fixCount == 0)
    #expect(plan.diagnostics.count == 1)
  }

  @Test("Reject every member of a conflicting compound fix")
  func compoundConflict() throws {
    let project = try Project()
    let first = try project.file("First.swift", text: "let first = 1")
    let second = try project.file("Second.swift", text: "let second = 2")
    let firstSource = try #require(first.syntaxNodes(of: .integerLiteral).first)
      .source
    let secondSource = try #require(second.syntaxNodes(of: .integerLiteral)
      .first).source
    let plan = CorrectionPlan.prepare(
      reports: [report([
        SourceFix(edits: [
          firstSource.replacement(with: "3"),
          secondSource.replacement(with: "4"),
        ]),
        SourceFix(edits: [firstSource.replacement(with: "5")]),
      ])],
      rootPath: project.root.path
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 2)
    #expect(plan.fixCount == 0)
  }

  @Test("Reject different insertions at the same position")
  func coincidentInsertions() throws {
    let project = try Project()
    let file = try project.file("Value.swift", text: "let value = 1")
    let start = try file.source.slice(0..<0)
    let plan = CorrectionPlan.prepare(
      reports: [report([
        SourceFix(edits: [start.replacement(with: "// First\n")]),
        SourceFix(edits: [start.replacement(with: "// Second\n")]),
      ])],
      rootPath: project.root.path
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 2)
  }

  @Test("Reject a compound fix when one target is outside the report scope")
  func compoundScope() throws {
    let project = try Project()
    let first = try project.file("First.swift", text: "let first = 1")
    let second = try project.file("Second.swift", text: "let second = 2")
    let fix = try SourceFix(edits: [
      first.source.replacement(with: "let first = 3"),
      second.source.replacement(with: "let second = 4"),
    ])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])],
      rootPath: project.root.path, reportPaths: ["First.swift"]
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 1)
  }

  @Test("Reject canonically equal text with different UTF-8 bytes")
  func changedUnicode() throws {
    let project = try Project()
    let file = try project.file("Value.swift", text: "let café = 1")
    let fix =
      try SourceFix(edits: [file.source.replacement(with: "let café = 2")])
    try Data("let cafe\u{301} = 1".utf8)
      .write(to: URL(fileURLWithPath: file.path))
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])],
      rootPath: project.root.path
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 1)
  }

  @Test("Reject syntax errors before applying any member of a fix")
  func parseFailure() throws {
    let project = try Project()
    let first = try project.file("First.swift", text: "let first = 1")
    let second = try project.file("Second.swift", text: "let second = 2")
    let fix = try SourceFix(edits: [
      first.source.replacement(with: "let first = {"),
      second.source.replacement(with: "let second = 4"),
    ])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])],
      rootPath: project.root.path
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 1)
  }

  @Test("Apply independent valid fixes beside rejected fixes")
  func independentFixes() throws {
    let project = try Project()
    let first = try project.file("First.swift", text: "let first = 1")
    let second = try project.file("Second.swift", text: "let second = 2")
    let plan = try CorrectionPlan.prepare(
      reports: [report([
        SourceFix(edits: [first.source.replacement(with: "let first = {")]),
        SourceFix(edits: [second.source.replacement(with: "let second = 4")]),
      ])],
      rootPath: project.root.path
    )
    #expect(plan.changes.map(\.path) == [second.path])
    #expect(plan.fixCount == 1)
    #expect(plan.diagnostics.count == 1)
  }

  @Test(
    "Reject changes to other captured input files",
    arguments: [false, true]
  )
  func changedInputs(addFile: Bool) async throws {
    let project = try Project()
    let file = try project.file("First.swift", text: "let first = 1")
    let capture = try await SourceCapture.capture(SourceCapture.Scope(
      rootPath: project.root.path,
      selection: .sourceFiles(
        including: ["*.swift"], excluding: [], swiftPM: false, xcode: false
      )
    ))
    if addFile {
      _ = try project.file("Second.swift", text: "let second = 2")
    } else {
      try Data("let first = 2".utf8).write(to: URL(fileURLWithPath: file.path))
    }
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate([capture])
    }
  }

  @Test("Reject protected rule source and file links", arguments: [false, true])
  func protectedTarget(link: Bool) throws {
    let project = try Project()
    var file = try project.file("Value.swift", text: "let value = 1")
    if link {
      let alias = project.root.appendingPathComponent("Alias.swift")
      try FileManager.default.createSymbolicLink(
        atPath: alias.path,
        withDestinationPath: file.path
      )
      file = try FileCollector.collect(fileAt: alias.path)
    }
    let fix =
      try SourceFix(edits: [file.source.replacement(with: "let value = 2")])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])], rootPath: project.root.path,
      protectedPaths: link ? [] : [file.path]
    )
    #expect(plan.changes.isEmpty)
    #expect(plan.diagnostics.count == 1)
  }

  @Test("Reject hard links before replacement", arguments: [false, true])
  func hardLinks(linkBeforePlanning: Bool) async throws {
    let project = try Project()
    let file = try project.file("Value.swift", text: "let value = 1")
    let alias = project.root.appendingPathComponent("Alias.swift")
    let source = URL(fileURLWithPath: file.path)
    if linkBeforePlanning {
      try FileManager.default.linkItem(at: source, to: alias)
    }
    let fix = try SourceFix(edits: [
      file.source.replacement(with: "let value = 2"),
    ])
    let plan = CorrectionPlan.prepare(
      reports: [report([fix])], rootPath: project.root.path
    )
    if linkBeforePlanning {
      #expect(plan.changes.isEmpty)
      #expect(plan.diagnostics.count == 1)
    } else {
      try FileManager.default.linkItem(at: source, to: alias)
      await #expect(throws: CorrectionPlan.ApplicationError.self) {
        try await plan.apply(captures: [])
      }
    }
    #expect(try Data(contentsOf: source) == Data("let value = 1".utf8))
    #expect(try Data(contentsOf: alias) == Data(contentsOf: source))
  }

  private func report(_ fixes: [SourceFix]) -> RuleReport {
    let offenders = fixes.map {
      Offender(
        description: "source correction",
        location: .start(of: $0.edits[0].source.filePath)
      )
    }
    return RuleReport(
      id: "source", name: "Source matches the rule", enforcement: .enforced,
      hint: nil, location: .start(of: "/Bylaws.swift"),
      violations: Violations(
        rule: "match the rule", offenders: offenders,
        checkedCount: offenders.count,
        witnesses: Array(repeating: nil, count: offenders.count),
        fixes: fixes.map(Optional.some)
      ),
      warnings: []
    )
  }

  private struct Project {
    private let storage: TemporaryProject

    var root: URL { storage.rootURL }

    init() throws {
      storage = try TemporaryProject(
        files: [:], directoryNamePrefix: "bylaws-corrections"
      )
    }

    func file(_ name: String, text: String) throws -> SourceFile {
      try storage.write(text, to: name)
      return try FileCollector.collect(fileAt: storage.fileURL(for: name).path)
    }
  }
}
