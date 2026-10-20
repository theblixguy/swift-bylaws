import Foundation
import Testing

@Suite("Portable CLI source corrections")
struct CLICorrectionProcessTests {
  private static let original =
    "\u{feff}// café 😀\r\nlet first = 0xdead_beef\r\nlet second = 0xa2\r\nlet binary = 0b101\r\n"
  private static let corrected =
    "\u{feff}// café 😀\r\nlet first = 0xDEAD_BEEF\r\nlet second = 0xA2\r\nlet binary = 0b101\r\n"
  private static let hexRule = #"""
  let app = Codebase(including: ["Sources/**"])
  Rule("hex", "Hex digits use uppercase letters") {
    try await app.syntaxNodes(of: .integerLiteral)
      .violations(matching: Matcher<SourceNode>("contain lowercase hex digits") {
        $0.text.hasPrefix("0x") && $0.text.contains(/[a-f]+/)
      })
      .withFix("Use uppercase hex digits") { context in
        for part in try context.source.matches(of: /[a-f]+/) {
          part.replacement(with: part.text.uppercased())
        }
      }
  }
  """#
  private static let pairedRule = """
  let app = Codebase(including: ["Sources/**"])
  Rule("paired-names", "Related classes use new names") {
    try await app.classes
      .violations(matching: Matcher<Class>("use the old primary name") {
        $0.name == "Primary"
      })
      .withFix("Rename related classes") { context in
        let companions = try await context.codebase.classes.named("Companion")
        let companion = try companions.only()
        try context.offender.nameSource.replacement(with: "Main")
        try companion.nameSource.replacement(with: "Helper")
      }
  }
  """

  @Test("Normal lint reports fixes without changing source")
  func lintIsReadOnly() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )

    let result = try project.run()

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("hex"))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
    #expect(result.standardError.isEmpty)
  }

  @Test("Autocorrect applies regex edits and reports final passing check")
  func correctHex() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )

    let result = try project.run("--autocorrect")

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("Checked 1 rule: 0 violations."))
    #expect(result.standardError.contains("Corrected 1 file:"))
    #expect(try sourceBytes(in: project) == Data(Self.corrected.utf8))
  }

  @Test("Dry run prints patch and keeps original source")
  func previewHex() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )

    let result = try project.run("--autocorrect", "--dry-run")

    #expect(result.status == 1)
    #expect(result.standardError.contains("--- "))
    #expect(result.standardError.contains("+++ "))
    #expect(result.standardError.contains("+let first = 0xDEAD_BEEF"))
    #expect(result.standardError.contains("+let second = 0xA2"))
    #expect(!result.standardError.contains("Corrected "))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  @Test("Compound correction updates both files before verification")
  func pairedNames() throws {
    let project = try pairedProject()

    let result = try project.run("--autocorrect")

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("0 violations"))
    #expect(result.standardError.contains("Corrected 2 files:"))
    #expect(try sourceBytes(in: project) == Data("class Main {}".utf8))
    #expect(try sourceBytes(in: project, path: "Sources/App/Companion.swift")
      == Data("class Helper {}".utf8))
  }

  @Test("Report output cannot overwrite correction inputs", arguments: [
    "source", "rules", "symbolic-link", "hard-link", "explicit-rules",
  ], [false, true])
  func reportInputCollision(_ target: String, dryRun: Bool) throws {
    let project = try CLIProcessProject(
      source: Self.original, rules: Self.hexRule,
      extraFiles: ["Policy.rules": Self.hexRule]
    )
    let source = project.root.appendingPathComponent("Sources/App/App.swift")
    let output = switch target {
    case "source": source
    case "rules": project.root.appendingPathComponent("Bylaws.swift")
    case "explicit-rules": project.root.appendingPathComponent("Policy.rules")
    default: project.root.appendingPathComponent("report.json")
    }
    if target == "symbolic-link" {
      try FileManager.default.createSymbolicLink(
        at: output,
        withDestinationURL: source
      )
    } else if target == "hard-link" {
      try FileManager.default.linkItem(at: source, to: output)
    }
    let originalOutput = try Data(contentsOf: output)
    var arguments = ["--autocorrect", "--output", output.path]
    if dryRun { arguments.append("--dry-run") }
    if target == "explicit-rules" { arguments += ["--rules", "Policy.rules"] }

    let result = try project.run(arguments: arguments, environment: [:])

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("report output"))
    #expect(try Data(contentsOf: output) == originalOutput)
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  @Test("Correction writes a separate final report")
  func reportOutput() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )
    let output = project.root.appendingPathComponent("report.json")

    let result = try project.run(
      "--autocorrect", "--format", "json", "--output", output.path
    )

    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(try sourceBytes(in: project) == Data(Self.corrected.utf8))
    let json = try #require(
      JSONSerialization
        .jsonObject(with: Data(contentsOf: output)) as? [String: Any]
    )
    let summary = try #require(json["summary"] as? [String: Int])
    #expect(summary["violations"] == 0)
  }

  @Test("Correction errors leave report output unchanged")
  func errorOutput() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )
    let output = project.root.appendingPathComponent("report.json")
    let original = Data("Previous report".utf8)
    try original.write(to: output)

    let result = try project.run(
      "--autocorrect", "--record-baseline", "Accepted.swift", "--output",
      output.path
    )

    #expect(result.status == 2)
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
    #expect(try Data(contentsOf: output) == original)
  }

  @Test("Portable verification errors retain changed paths and prior report")
  func verificationFailure() throws {
    let project = try CLIProcessProject(
      source: "class Original {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("names", "Classes use updated names") {
        let selected = try await app.classes.named("Original")
        let original = try selected.only()
        try await app.classes.violations(of: .named("Updated")).withFix {
          try original.nameSource.replacement(with: "Updated")
        }
      }
      """
    )
    let output = project.root.appendingPathComponent("report.json")
    let previous = Data("Previous report".utf8)
    try previous.write(to: output)

    let result = try project.run(
      "--autocorrect", "--quiet", "--output", output.path
    )

    #expect(result.status == 2)
    #expect(result.standardOutput
      .contains("Cannot verify the corrected source"))
    #expect(result.standardOutput.contains("Sources/App/App.swift"))
    #expect(result.standardOutput
      .contains("the selection must contain one element"))
    #expect(try sourceBytes(in: project) == Data("class Updated {}".utf8))
    #expect(try Data(contentsOf: output) == previous)
  }

  @Test("Argument errors cannot overwrite explicit rule source")
  func argumentErrorOutput() throws {
    let project = try CLIProcessProject(
      source: Self.original, rules: Self.hexRule,
      extraFiles: ["Policy.rules": Self.hexRule]
    )
    let output = project.root.appendingPathComponent("Policy.rules")

    let result = try project.run(
      "--skip-tests", "--test-filter", "Rules",
      "--rules", "Policy.rules", "--output", output.path
    )

    #expect(result.status == 2)
    #expect(result.standardError.contains("report output overlaps"))
    #expect(try Data(contentsOf: output) == Data(Self.hexRule.utf8))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  @Test("Report scope rejects entire correction spanning two files")
  func pairedScope() throws {
    let project = try pairedProject()

    let result = try project.run(
      "--autocorrect", "--report-path", "Sources/App/App.swift"
    )

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("outside --report-path"))
    #expect(!result.standardError.contains("Corrected "))
    #expect(try sourceBytes(in: project) == Data("class Primary {}".utf8))
    #expect(try sourceBytes(in: project, path: "Sources/App/Companion.swift")
      == Data("class Companion {}".utf8))
  }

  @Test("Nested override keeps shared rule ID during CLI correction")
  func overrideCorrection() throws {
    let project = try CLIProcessProject(
      source: "class Root {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes", "Classes are final") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.source.slice(0..<0).replacement(with: "final ")
        }
      }
      """,
      extraFiles: [
        "Sources/Child/Child.swift": "class Child {}",
        "Sources/Child/Bylaws.swift": """
        let app = Codebase(including: ["**"])
        Override("final-classes", reason: "Child classes keep a local correction") {
          try await app.classes.violations(of: .isFinal).withFix { context in
            try context.source.slice(0..<0).replacement(with: "final ")
          }
        }
        """,
      ]
    )

    let result = try project.run("--autocorrect")

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("0 violations"))
    #expect(result.standardError.contains("Corrected 2 files:"))
    #expect(try sourceBytes(in: project) == Data("final class Root {}".utf8))
    #expect(try sourceBytes(in: project, path: "Sources/Child/Child.swift")
      == Data("final class Child {}".utf8))
  }

  @Test("Accepted baseline violations remain unchanged")
  func acceptedBaseline() throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )
    let baseline = project.root.appendingPathComponent("Accepted.swift")
    let recording = try project.run("--record-baseline", baseline.path)
    try #require(recording.status == 0)

    let result = try project.run("--autocorrect", "--baseline", baseline.path)

    #expect(result.status == 0)
    #expect(result.standardOutput.contains("0 violations"))
    #expect(!result.standardError.contains("Corrected "))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  @Test("Autocorrect applies one batch and reports remaining failure")
  func oneCycle() throws {
    let project = try CLIProcessProject(
      source: "class First {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("names", "Classes are final") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          if context.offender.name == "First" {
            try context.offender.nameSource.replacement(with: "Second")
          } else {
            try context.offender.nameSource.replacement(with: "First")
          }
        }
      }
      """
    )

    let result = try project.run("--autocorrect")

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("Second violates"))
    #expect(result.standardError.contains("Corrected 1 file:"))
    #expect(try sourceBytes(in: project) == Data("class Second {}".utf8))
  }

  @Test(
    "Empty and unchanged proposals leave violations without writes",
    arguments: [
      "", "try context.source.replacement(with: context.source.text)",
    ]
  )
  func ineffectiveFix(_ body: String) throws {
    let project = try CLIProcessProject(
      source: "class App {}",
      rules: """
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes", "Classes are final") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          \(body)
        }
      }
      """
    )

    let result = try project.run("--autocorrect")

    #expect(result.status == 1)
    #expect(result.standardOutput.contains("App violates"))
    #expect(result.standardError.isEmpty)
    #expect(try sourceBytes(in: project) == Data("class App {}".utf8))
  }

  @Test(
    "Correction options reject incomplete or conflicting commands",
    arguments: [false, true]
  )
  func incompatibleOptions(recordBaseline: Bool) throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )
    let baseline = project.root.appendingPathComponent("Accepted.swift")
    let arguments = recordBaseline
      ? ["--autocorrect", "--record-baseline", baseline.path]
      : ["--dry-run"]

    let result = try project.run(arguments: arguments, environment: [:])

    #expect(result.status == 2)
    #expect(result.standardOutput.contains(recordBaseline
        ? "--autocorrect cannot be combined with --record-baseline"
        : "--dry-run must be used with --autocorrect"))
    #expect(!FileManager.default.fileExists(atPath: baseline.path))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  @Test("Skipping tests rejects Swift Testing test selection", arguments: [
    "--test-package", "--test-filter",
  ])
  func conflictingTestOptions(_ option: String) throws {
    let project = try CLIProcessProject(
      source: Self.original,
      rules: Self.hexRule
    )

    let result = try project.run(
      "--autocorrect",
      "--skip-tests",
      option,
      "Tests"
    )

    #expect(result.status == 2)
    #expect(result.standardOutput.contains("--skip-tests cannot be combined"))
    #expect(try sourceBytes(in: project) == Data(Self.original.utf8))
  }

  private func pairedProject() throws -> CLIProcessProject {
    try CLIProcessProject(
      source: "class Primary {}", rules: Self.pairedRule,
      extraFiles: ["Sources/App/Companion.swift": "class Companion {}"]
    )
  }

  private func sourceBytes(
    in project: CLIProcessProject, path: String = "Sources/App/App.swift"
  ) throws -> Data {
    try Data(contentsOf: project.root.appendingPathComponent(path))
  }
}
