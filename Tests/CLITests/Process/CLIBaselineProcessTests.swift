import Foundation
import Testing

@Suite("Bylaws baseline process")
struct CLIBaselineProcessTests {
  @Test("Recorded baseline applies to the next run")
  func baselineRecording() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let baseline = project.root.appendingPathComponent("Baseline.swift")

    let recording = try project.run(
      "--record-baseline",
      baseline.path
    )
    let accepted = try project.run("--baseline", baseline.path)

    #expect(recording.status == 0)
    #expect(recording.standardOutput.contains("Recorded 1 entry"))
    #expect(FileManager.default.fileExists(atPath: baseline.path))
    #expect(accepted.status == 0)
    #expect(accepted.standardOutput.contains("0 violations"))
  }

  @Test("Rule filters cannot be used while recording a baseline")
  func baselineRecordingWithRuleSelection() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let baseline = project.root.appendingPathComponent("Baseline.swift")

    let result = try project.run(
      "--record-baseline",
      baseline.path,
      "--only",
      "final-classes"
    )

    #expect(result.status == 2)
    #expect(
      result.standardOutput.contains(
        "--record-baseline cannot be combined with --only, --skip or --report-path"
      )
    )
    #expect(!FileManager.default.fileExists(atPath: baseline.path))
  }

  @Test("Baseline entry is stale after its violation is fixed")
  func staleBaselineEntry() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let baseline = project.root.appendingPathComponent("Baseline.swift")
    _ = try project.run("--record-baseline", baseline.path)
    try project.writeSource("final class Bad {}")

    let result = try project.run("--baseline", baseline.path)

    #expect(result.status == 1)
    #expect(result.standardOutput
      .contains("baseline entry no longer matches a violation"))
    #expect(result.standardOutput.contains("final-classes: Bad"))
  }

  @Test("Rule selection uses baseline entries from selected rules only")
  func selectedRulesIgnoreOtherBaselineEntries() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}\nfinal class Good {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])

      Rule("failing", "Classes are final") {
        app.classes.named("Bad").violations(of: .isFinal)
      }

      Rule("passing", "Good is final") {
        app.classes.named("Good").violations(of: .isFinal)
      }
      """
    )
    let baseline = project.root.appendingPathComponent("Baseline.swift")
    _ = try project.run("--record-baseline", baseline.path)
    try project.writeSource("final class Bad {}\nfinal class Good {}")

    let result = try project.run(
      "--baseline", baseline.path,
      "--only", "passing"
    )

    #expect(result.status == 0)
    #expect(!result.standardOutput.contains("matched no violation"))
  }

  @Test("Baseline recording writes one copy of each entry")
  func baselineRecordingDeduplicates() throws {
    let project = try CLIProcessProject(
      source: """
      func run() {
        print("first")
        print("second")
      }
      """,
      rules: """
      let app = Codebase(including: ["Sources/**"])

      Rule("prints", "Print calls are absent") {
        app.calls.violations(matching: .references("print"))
      }
      """
    )
    let baseline = project.root.appendingPathComponent("Baseline.swift")

    let result = try project.run("--record-baseline", baseline.path)
    let contents = try String(contentsOf: baseline, encoding: .utf8)

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Recorded 1 entry"))
    #expect(contents.components(separatedBy: "Entry(").count - 1 == 1)
  }

  @Test("A missing baseline directory reports a configuration error")
  func baselineWriteFailure() throws {
    let project = try CLIProcessProject(
      source: "class Bad {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let baseline = project.root
      .appendingPathComponent("Missing/Baseline.swift")

    let result = try project.run("--record-baseline", baseline.path)

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("could not write"))
    #expect(result.standardError.isEmpty)
  }
}
