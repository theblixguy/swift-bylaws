#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsTestSupport
  import Foundation
  import Subprocess
  import Testing

  #if canImport(System)
    import System
  #else
    import SystemPackage
  #endif

  @Suite("Swift Testing CLI corrections")
  struct SwiftTestingCorrectionProcessTests {
    @Test(
      "Native rule previews, corrects and reports passing verification",
      .timeLimit(.minutes(10))
    )
    func correctionLifecycle() async throws {
      let consumer = try SwiftTestingReportConsumer(enforcement: .enforced)
      let original = Data("class Screen {}\n".utf8)
      let corrected = Data("class Updated {}\n".utf8)

      let lint = try await run(consumer)

      try #require(
        lint.status == .exited(1),
        "stdout:\n\(lint.standardOutput)\nstderr:\n\(lint.standardError)"
      )
      try expectReport(lint, violations: 1)
      #expect(try Data(contentsOf: consumer.sourceFile) == original)
      let resolved = consumer.root.appendingPathComponent("Package.resolved")
      let resolvedBytes = try Data(contentsOf: resolved)

      let collision = try await run(
        consumer, arguments: ["--output", resolved.path]
      )

      #expect(collision.status == .exited(2), "\(collision.standardError)")
      #expect(collision.standardOutput.contains("report output overlaps"))
      #expect(try Data(contentsOf: resolved) == resolvedBytes)
      #expect(try Data(contentsOf: consumer.sourceFile) == original)

      let preview = try await run(
        consumer, arguments: [
          "--autocorrect", "--dry-run", "--report-path",
          "Sources/App/Screen.swift",
        ]
      )

      #expect(preview.status == .exited(1), "\(preview.standardError)")
      try expectReport(preview, violations: 1)
      #expect(preview.standardError.contains("""
      @@ -1,1 +1,1 @@
      -class Screen {}
      +class Updated {}
      """))
      #expect(!preview.standardError.contains("Corrected "))
      #expect(try Data(contentsOf: consumer.sourceFile) == original)

      let correction = try await run(consumer, arguments: [
        "--autocorrect", "--report-path", "Sources/App/Screen.swift",
      ])

      #expect(correction.status == .exited(0), "\(correction.standardError)")
      try expectReport(correction, violations: 0)
      #expect(correction.standardError.contains("Corrected 1 file:"))
      #expect(correction.standardError.contains("Sources/App/Screen.swift"))
      #expect(try Data(contentsOf: consumer.sourceFile) == corrected)

      let final = try await run(consumer)

      #expect(final.status == .exited(0), "\(final.standardError)")
      try expectReport(final, violations: 0)
      #expect(try Data(contentsOf: consumer.sourceFile) == corrected)
    }

    @Test(
      "Missing verification report retains applied edit and previous output",
      .timeLimit(.minutes(10))
    )
    func missingVerificationReport() async throws {
      let consumer = try SwiftTestingReportConsumer(
        enforcement: .enforced,
        additionalTests: """
        @Test func reportsOnlyFailure() async throws {
          let violations = try await app.classes.violations(of: .named("Updated"))
          if !violations.offenders.isEmpty {
            try await reportRename()
          }
        }
        """
      )
      let output = consumer.root.appendingPathComponent("report.json")
      let previousOutput = Data("Previous report\n".utf8)
      try previousOutput.write(to: output)

      let result = try await run(
        consumer, function: "reportsOnlyFailure",
        arguments: ["--autocorrect", "--output", output.path]
      )

      try #require(
        result.status == .exited(2),
        "stdout:\n\(result.standardOutput)\nstderr:\n\(result.standardError)"
      )
      try #require(
        !result.standardOutput.isEmpty,
        "stderr:\n\(result.standardError)"
      )
      let report = try #require(JSONSerialization.jsonObject(
        with: Data(result.standardOutput.utf8)
      ) as? [String: Any])
      let events = try #require(report["events"] as? [[String: Any]])
      let message = events.compactMap { $0["message"] as? String }
        .joined(separator: "\n")
      #expect(message.contains("The correction changed these files:"))
      #expect(message.contains("Sources/App/Screen.swift"))
      #expect(message
        .contains("rule 'rename-class' did not report during verification"))
      #expect(try Data(contentsOf: consumer.sourceFile)
        == Data("class Updated {}\n".utf8))
      #expect(try Data(contentsOf: output) == previousOutput)
    }

    @Test(
      "Formatting rule previews applies and verifies combined layouts",
      .timeLimit(.minutes(10))
    )
    func formattingLifecycle() async throws {
      let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Corrections/Formatting")
      let helpers = try [
        "StatementSpacingRewriter.swift",
        "PropertyGroupingRewriter.swift",
        "MultilineCallRewriter.swift",
        "FormattingRule.swift",
      ].map {
        try String(
          contentsOf: directory.appendingPathComponent($0),
          encoding: .utf8
        )
      }.joined(separator: "\n")
      let consumer =
        try SwiftTestingReportConsumer(additionalTests: helpers + """

        @Test("Source follows layout")
        func reportsFormatting() async throws {
          let violations = try await FormattingRule.violations(in: app)
          violations.report(ruleID: "formatting", enforcement: .enforced)
        }
        """)
      try consumer.writeSource(FormattingMock.combined)
      let preview = try await run(
        consumer, function: "reportsFormatting",
        arguments: ["--autocorrect", "--dry-run"]
      )

      try #require(
        preview.status == .exited(1),
        "stdout:\n\(preview.standardOutput)\nstderr:\n\(preview.standardError)"
      )
      try expectReport(preview, violations: 1, ruleID: "formatting")
      #expect(preview.standardError.contains("@Environment"))
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
        == FormattingMock.combined)

      let correction = try await run(
        consumer, function: "reportsFormatting", arguments: ["--autocorrect"]
      )

      try #require(
        correction.status == .exited(0),
        "stdout:\n\(correction.standardOutput)\nstderr:\n\(correction.standardError)"
      )
      try expectReport(correction, violations: 0, ruleID: "formatting")
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
        == FormattingMock.formattedCombined)
    }

    @Test(
      "Layout builder previews applies and verifies a native rule",
      .timeLimit(.minutes(10))
    )
    func layoutBuilderLifecycle() async throws {
      let consumer = try SwiftTestingReportConsumer(additionalTests: """
      @Test("Class attributes use separate declaration line")
      func reportsLayout() async throws {
        let violations = try await app.classes.violations("Order attributes on one line") { declaration in
          if !declaration.attributes.isEmpty {
            try declaration.attributes.replacement {
              Line {
                declaration.attributes.sorted { $0.name > $1.name }
              }
            }
          }
        }
        violations.report(ruleID: "attribute-layout", enforcement: .enforced)
      }
      """)
      let original = "@MainActor\n@available(*, deprecated) class Screen {}\n"
      let expected = "@available(*, deprecated) @MainActor\nclass Screen {}\n"
      try consumer.writeSource(original)

      let preview = try await run(
        consumer, function: "reportsLayout",
        arguments: ["--autocorrect", "--dry-run"]
      )
      try #require(
        preview.status == .exited(1),
        "\(preview.standardOutput)\n\(preview.standardError)"
      )
      try expectReport(preview, violations: 1, ruleID: "attribute-layout")
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8) ==
        original)

      let correction = try await run(
        consumer, function: "reportsLayout", arguments: ["--autocorrect"]
      )
      try #require(
        correction.status == .exited(0),
        "\(correction.standardOutput)\n\(correction.standardError)"
      )
      try expectReport(correction, violations: 0, ruleID: "attribute-layout")
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8) ==
        expected)
    }

    private func expectReport(
      _ result: Result,
      violations: Int,
      ruleID: String = "rename-class",
      sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
      let report = try #require(JSONSerialization.jsonObject(
        with: Data(result.standardOutput.utf8)
      ) as? [String: Any], sourceLocation: sourceLocation)
      let summary = try #require(
        report["summary"] as? [String: Int], sourceLocation: sourceLocation
      )
      #expect(summary["checkedRules"] == 1, sourceLocation: sourceLocation)
      #expect(
        summary["violations"] == violations,
        sourceLocation: sourceLocation
      )
      let rules = try #require(
        report["rules"] as? [[String: Any]], sourceLocation: sourceLocation
      )
      #expect(
        rules.compactMap { $0["id"] as? String } == [ruleID],
        sourceLocation: sourceLocation
      )
    }

    @concurrent
    private func run(
      _ consumer: SwiftTestingReportConsumer,
      function: String = "reportsFix",
      arguments: [String] = []
    ) async throws -> Result {
      try Task.checkCancellation()
      let executable = try ExecutableLocator.locate(
        named: "bylaws", overriddenBy: "BYLAWS_CLI_BINARY",
        relativeTo: #filePath
      )
      let environment = Environment.inherit.updating([
        "BYLAWS_SWIFT_TESTING_RULE_SESSION": nil,
        "BYLAWS_SOURCE_CAPTURE_DIRECTORY": nil,
        "BYLAWS_SOURCE_CAPTURE_ID": nil,
        "BYLAWS_INDEX_STORE": nil,
        "BYLAWS_FRESH_INDEX_STORE": nil,
        "BYLAWS_FRESH_INDEX_ROOT": nil,
        "BYLAWS_CORRECTION_ACTIVE": nil,
        "BYLAWS_SOURCE_ONLY": nil,
      ])
      var options = PlatformOptions()
      options.processGroupID = 0
      options.teardownSequence = [
        .send(
          signal: .interrupt, toProcessGroup: true,
          allowedDurationToNextStep: .seconds(35)
        ),
      ]
      let result = try await Subprocess.run(
        .path(FilePath(executable.path)),
        arguments: Arguments([
          "lint", "--root", consumer.root.path, "--source-only",
          "--test-filter", function, "--format", "json",
        ] + arguments),
        environment: environment,
        workingDirectory: FilePath(consumer.root.path),
        platformOptions: options,
        output: .string(limit: 8 * 1024 * 1024),
        error: .string(limit: 8 * 1024 * 1024)
      )
      try Task.checkCancellation()
      return Result(
        status: result.terminationStatus,
        standardOutput: result.standardOutput,
        standardError: result.standardError
      )
    }

    private struct Result: Sendable {
      let status: TerminationStatus
      let standardOutput: String
      let standardError: String
    }
  }
#endif
