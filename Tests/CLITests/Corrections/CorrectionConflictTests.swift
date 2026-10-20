import BylawsCore
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction conflicts")
struct CorrectionConflictTests {
  @Test("Disjoint edits report differing Swift language modes")
  func languageModes() throws {
    let original = "let first = 1\nlet second = 2\n"
    let project = try TemporaryProject(files: ["Values.swift": original])
    let path = project.fileURL(for: "Values.swift").path
    let swift5 = try FileCollector.collect(fileAt: path, swiftLanguageMode: .v5)
    let swift6 = try FileCollector.collect(fileAt: path, swiftLanguageMode: .v6)
    let first = try #require(swift5.syntaxNodes(of: .integerLiteral).first)
      .source
    let second = try #require(swift6.syntaxNodes(of: .integerLiteral).last)
      .source
    try #require(!first.range.overlaps(second.range))
    let fixes = [
      SourceFix(edits: [first.replacement(with: "3")]),
      SourceFix(edits: [second.replacement(with: "4")]),
    ]
    let offenders = [
      Offender(description: "first literal", location: .start(of: path)),
      Offender(description: "second literal", location: .start(of: path)),
    ]
    let report = RuleReport(
      id: "values", name: "Replace literals", enforcement: .enforced,
      hint: nil,
      location: .start(of: project.fileURL(for: "Bylaws.swift").path),
      violations: Violations(
        rule: "replace literals", offenders: offenders, checkedCount: 2,
        witnesses: [nil, nil], fixes: fixes.map(Optional.some)
      ),
      warnings: []
    )

    let plan = CorrectionPlan.prepare(
      reports: [report], rootPath: project.rootURL.path
    )

    #expect(plan.changes.isEmpty)
    #expect(plan.fixCount == 0)
    #expect(plan.diagnostics.count == 2)
    for diagnostic in plan.diagnostics {
      #expect(diagnostic.message.contains(path))
      #expect(diagnostic.message.contains("Swift language modes: 5, 6"))
      #expect(diagnostic.message.contains("Use the same swiftLanguageMode"))
      #expect(!diagnostic.message.contains("overlap"))
    }
    #expect(try Data(contentsOf: project.fileURL(for: "Values.swift"))
      == Data(original.utf8))
  }
}
