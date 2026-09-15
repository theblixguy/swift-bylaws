import Foundation
import Testing

@Suite("Folder rules from the CLI")
struct CLIFolderDiscoveryTests {
  @Test("Run folder rules in a Bazel project")
  func folderRules() throws {
    let project = try CLIProcessProject(
      source: "class App {}",
      rules: nil,
      extraFiles: [
        "MODULE.bazel": "",
        "Modules/Bylaws.swift": CLIProcessMock.finalClassesRule,
        "Modules/Sources/Parent.swift": "final class Parent {}",
        "Modules/Billing/Bylaws.swift": """
        let codebase = Codebase(including: ["Sources/**"])
        Override("final-classes", reason: "billing classes must be public") {
          codebase.classes.violations(of: .isPublic)
        }
        """,
        "Modules/Billing/Sources/Invoice.swift": "final class Invoice {}",
      ],
      writesProjectMarker: false
    )

    let result = try project.runResolvingRoot()
    let inspection = try project.runRules(
      "--for",
      project.root
        .appendingPathComponent("Modules/Billing/Sources/Invoice.swift").path
    )

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("Invoice"))
    #expect(result.standardOutput.contains("1 violation"))
    #expect(inspection.status == 0)
    #expect(inspection.standardOutput.contains("Modules/Billing/Bylaws.swift"))
    #expect(inspection.standardOutput
      .contains("override: billing classes must be public"))
    #expect(!inspection.standardOutput.contains("Modules/Bylaws.swift"))
  }
}
