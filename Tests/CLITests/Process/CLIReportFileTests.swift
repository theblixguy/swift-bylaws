import BylawsTestSupport
import Foundation
import Testing

@Suite("CLI report files")
struct CLIReportFileTests {
  @Test(
    "Report file matches standard output",
    arguments: ["json", "sarif", "xcode", "github"]
  )
  func reportFormats(format: String) throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let printed = try project.run("--format", format)

    let saved = try project.run("--format", format, "--output", "report.txt")
    let report = try String(
      contentsOf: project.root.appendingPathComponent("report.txt"),
      encoding: .utf8
    )

    #expect(saved.status == 1)
    #expect(saved.standardOutput.isEmpty)
    #expect(saved.standardError.contains("Bad"))
    #expect(report == printed.standardOutput)
  }

  @Test(
    "Rules resolve from project root and report resolves from working directory"
  )
  func separateDirectories() throws {
    let caller = try TemporaryProject(files: [:])
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run(
      "--rules", "Bylaws.swift", "--format", "json", "--output", "report.json",
      from: caller.rootURL
    )
    let report = try Data(contentsOf: caller.rootURL
      .appendingPathComponent("report.json"))
    let json = try #require(JSONSerialization
      .jsonObject(with: report) as? [String: Any])
    let summary = try #require(json["summary"] as? [String: Any])

    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.isEmpty)
    #expect(summary["checkedRules"] as? Int == 1)
    #expect(summary["violations"] as? Int == 0)
  }

  @Test("Configuration errors reach report file and standard error")
  func ruleErrors() throws {
    let project = try CLIProcessProject(source: "", rules: "Rule(")

    let result = try project.run("--format", "json", "--output", "report.json")
    let report = try Data(contentsOf: project.root
      .appendingPathComponent("report.json"))
    let json = try #require(JSONSerialization
      .jsonObject(with: report) as? [String: Any])

    #expect(result.status == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("error:"))
    #expect((json["events"] as? [[String: Any]])?.isEmpty == false)
  }

  @Test("Report write failure returns configuration error")
  func writeFailure() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run("--output", "Missing/report.json")

    #expect(result.status == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("cannot write report"))
    #expect(result.standardError.contains("Missing/report.json"))
  }

  @Test("Quiet successful run writes empty text report")
  func emptyReport() throws {
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run("--quiet", "--output", "report.txt")
    let report = try Data(contentsOf: project.root
      .appendingPathComponent("report.txt"))

    #expect(result.status == 0)
    #expect(report.isEmpty)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.isEmpty)
  }

  @Test("Baseline resolves from project root outside working directory")
  func baselineRoot() throws {
    let caller = try TemporaryProject(files: [:])
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let recorded = try project.run("--record-baseline", "Baseline.swift")
    try #require(recorded.status == 0)

    let result = try project.run(
      "--rules",
      "Bylaws.swift",
      "--baseline",
      "Baseline.swift",
      from: caller.rootURL
    )

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("0 violations"))
  }

  @Test("Relative Codebase directory resolves from rules file")
  func codebaseDirectory() throws {
    let caller = try TemporaryProject(files: [:])
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: nil,
      extraFiles: [
        "Rules/Checks.swift": """
        let app = Codebase(root: .directory(".."), including: ["Sources/**"])
        Rule("final-classes", "Final classes") {
          app.classes.violations(of: .isFinal)
        }
        """,
      ]
    )

    let result = try project.run(
      "--rules",
      "Rules/Checks.swift",
      from: caller.rootURL
    )

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("Bad violates"))
  }

  @Test("Absolute output path replaces existing report")
  func absoluteOutput() throws {
    let caller = try TemporaryProject(files: ["report.txt": "Old report"])
    let project = try CLIProcessProject(
      source: "final class Good {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let output = caller.rootURL.appendingPathComponent("report.txt")

    let result = try project.run("--output", output.path)
    let report = try String(contentsOf: output, encoding: .utf8)

    #expect(result.status == 0)
    #expect(report == "Checked 1 rule: 0 violations.\n")
  }

  @Test("Baseline recording and report output cannot share a run")
  func baselineAndOutput() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )

    let result = try project.run(
      "--record-baseline",
      "Baseline.swift",
      "--output",
      "report.txt"
    )

    #expect(result.status == 2)
    #expect(result.standardError
      .contains("--record-baseline cannot be combined with --output"))
    #expect(!FileManager.default
      .fileExists(atPath: project.root.appendingPathComponent("Baseline.swift")
        .path))
  }

  @Test("Saved advisory report preserves warning and successful exit")
  func advisoryOutput() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes", "Final classes", enforcement: .advisory) {
        app.classes.violations(of: .isFinal)
      }
      """
    )

    let result = try project.run("--output", "report.txt")

    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("warning:"))
    #expect(result.standardError.contains("Bad"))
  }
}
