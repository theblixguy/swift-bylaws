import BylawsCore
import BylawsRunner
import BylawsSemantics
import Testing

@Suite("Folder rule reports")
struct FolderReportTests {
  @Test("An unmatched folder pattern reports only its specific warning")
  func unmatchedPattern() async throws {
    let app = Codebase(root: .sources([:]))
    let location = DeclarationLocation.start(of: "/project/Bylaws.swift")
    let findings = try await app.checkFolderLayout(
      matching: "Sources/App/*", containing: ["Views"]
    ).findings(reportedAt: location)
    let document = ReportDocument(reports: [RuleReport(
      id: "folders",
      name: "Features have Views folders",
      enforcement: .enforced,
      hint: nil,
      location: location,
      violations: findings.violations,
      warnings: findings.warnings
    )], diagnostics: [])
    #expect(document.events.map(\.message) == [
      "Features have Views folders: Folder pattern 'Sources/App/*' matched no folders. Check the pattern.",
    ])
  }
}
