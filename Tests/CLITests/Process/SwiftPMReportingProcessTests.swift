#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsRunner
  import BylawsSemantics
  import BylawsTestSupport
  import Foundation
  import Testing

  @Suite("SwiftPM rule reporting")
  struct SwiftPMReportingProcessTests {
    @Test(
      "Enforced child report retains fix, empty outcome and unrelated failure",
      .timeLimit(.minutes(10))
    )
    func reportingLifecycle() async throws {
      let consumer = try SwiftTestingReportConsumer(enforcement: .enforced)
      let original = Data("class Screen {}\n".utf8)
      let firstSession = session(in: consumer, phase: "first")

      let first = try await collect(consumer, session: firstSession)

      #expect(first.reports.count == 1)
      let report = try #require(first.reports.first)
      #expect(report.sessionID == firstSession.id)
      #expect(report.ruleID == "rename-class")
      #expect(report.enforcement == .enforced)
      #expect(report.baselineAccepted == [false])
      #expect(report.findings.violations.offenders.map(\.name) == ["Screen"])
      #expect(report.findings.violations.checkedCount == 1)
      let summary = try SwiftTestingRunSummary(
        data: Data(contentsOf: URL(fileURLWithPath: firstSession.directory)
          .appendingPathComponent("events.jsonl")),
        requiresMatchingTests: true
      )
      let function = try #require(summary.tests
        .first { $0.id == report.testID })
      #expect(function.name == "reportsFix()")
      #expect(function.kind == "function")
      #expect(function.isParameterized == false)
      #expect(summary.skippedTestIDs.isEmpty)
      #expect(first.indexStorePath == nil)
      #expect(URL(fileURLWithPath: first.packageRootPath)
        .resolvingSymlinksInPath().path == consumer.root.path)
      #expect(first.protectedSourcePaths.map {
        URL(fileURLWithPath: $0).resolvingSymlinksInPath()
      } ==
        [consumer.root.appendingPathComponent("Tests/RuleTests/Rules.swift")])
      let fix = try #require(report.findings.violations.fixes.first ?? nil)
      #expect(fix.title == "Rename class")
      #expect(fix.edits.count == 1)
      let edit = try #require(fix.edits.first)
      #expect(URL(fileURLWithPath: edit.source.filePath)
        .resolvingSymlinksInPath() == consumer.sourceFile)
      #expect(edit.source.range == 6..<12)
      #expect(edit.source.text == "Screen")
      #expect(Data(edit.source.file.text.utf8) == original)
      #expect(edit.replacement == "Updated")
      #expect(try Data(contentsOf: consumer.sourceFile) == original)
      #expect(first.captures.contains {
        guard case let .sourceFiles(including, _, _, _) = $0.scope.selection
        else { return false }
        return including == ["**"]
          && URL(fileURLWithPath: $0.scope.rootPath)
          .resolvingSymlinksInPath().path == consumer.root.path
      })
      let sourceCapture = try #require(first.captures.first {
        guard case let .sourceFiles(including, _, _, _) = $0.scope.selection
        else { return false }
        return including == ["Sources/App/**"]
      })
      #expect(sourceCapture.sessionID == firstSession.id)
      #expect(first.captures.allSatisfy { $0.sessionID == firstSession.id })
      let input = try #require(sourceCapture.inputs.first {
        URL(fileURLWithPath: $0.path).resolvingSymlinksInPath()
          == consumer.sourceFile
      })
      #expect(input.digest ==
        "095c8a9cf290bb1174a709ca806d070eaa57d8e148eae827219d2ce4aae33e81")
      try await SourceCapture.validate(first.captures)

      try consumer.writeSource("class Updated {}\n")
      let emptySession = session(in: consumer, phase: "empty")
      let empty = try await collect(consumer, session: emptySession)

      #expect(empty.reports.count == 1)
      let emptyReport = try #require(empty.reports.first)
      #expect(emptyReport.sessionID == emptySession.id)
      #expect(emptyReport.sessionID != report.sessionID)
      #expect(emptyReport.testID == report.testID)
      #expect(emptyReport.ruleID == "rename-class")
      #expect(emptyReport.enforcement == .enforced)
      #expect(emptyReport.findings.violations.checkedCount == 1)
      #expect(emptyReport.findings.violations.offenders.isEmpty)
      #expect(emptyReport.findings.violations.fixes.isEmpty)
      #expect(emptyReport.baselineAccepted.isEmpty)
      #expect(empty.captures.allSatisfy { $0.sessionID == emptySession.id })
      #expect(try Data(contentsOf: consumer.sourceFile)
        == Data("class Updated {}\n".utf8))
      try await SourceCapture.validate(empty.captures)

      try consumer.writeSource("class Screen {}\n")
      let failingSession = session(in: consumer, phase: "unrelated-failure")

      await #expect {
        try await collect(
          consumer, function: "reportsUnrelatedFailure", session: failingSession
        )
      } throws: { error in
        guard let error = error as? SwiftPMTestRunnerError,
              case let .processFailed(status, _) = error
        else { return false }
        return status != 0
      }
      let reportFiles = try FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: failingSession.directory),
        includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("report-") }
      #expect(reportFiles.count == 1)
      let failedReport = try SwiftTestingRuleSession.readReport(
        at: #require(reportFiles.first)
      )
      #expect(failedReport.sessionID == failingSession.id)
      #expect(failedReport.testID.contains("reportsUnrelatedFailure"))
      #expect(failedReport.findings.violations.offenders.map(\.name)
        == ["Screen"])
      #expect(try Data(contentsOf: consumer.sourceFile) == original)
    }

    private func session(
      in consumer: SwiftTestingReportConsumer,
      phase: String
    ) -> SwiftTestingRuleSession {
      SwiftTestingRuleSession(
        id: phase,
        directory: consumer.root.appendingPathComponent(
          ".build/bylaws-reporting-\(phase)"
        ).path,
        rootPath: consumer.root.path,
        isCorrection: true,
        sourceOnly: true
      )
    }

    private func collect(
      _ consumer: SwiftTestingReportConsumer,
      function: String = "reportsFix",
      session: SwiftTestingRuleSession
    ) async throws -> SwiftPMTestRun {
      try await SwiftPMTestRunner.collect(
        atRoot: consumer.root.path,
        filters: [function],
        swiftPMArguments: ["--disable-sandbox"],
        session: session
      )
    }
  }
#endif
