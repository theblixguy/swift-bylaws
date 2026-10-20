#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsSemantics
  import Foundation
  import Testing

  @Suite("Swift Testing report process")
  struct SwiftTestingReportProcessTests {
    @Test(
      "Ordinary attachments and collected reports preserve exact correction",
      .timeLimit(.minutes(10))
    )
    func reportingLifecycle() async throws {
      let consumer = try SwiftTestingReportConsumer()
      let original = Data("class Screen {}\n".utf8)
      let ordinary = try await consumer.run("reportsFix", phase: "ordinary")
      _ = try ordinary.completedTestID(named: "reportsFix")
      let attachmentFiles = try FileManager.default.contentsOfDirectory(
        at: ordinary.attachments, includingPropertiesForKeys: nil
      )

      #expect(attachmentFiles.map(\.lastPathComponent) == ["bylaws-fixes.json"])
      let attachment = try #require(attachmentFiles.first)
      let fixes = try JSONDecoder().decode(
        [SourceFix].self,
        from: Data(contentsOf: attachment)
      )
      try expectRename(fixes, at: consumer.sourceFile.path)
      let attachmentEvents = try ordinary.records()
        .filter { $0.payload.kind == "valueAttached" }
      #expect(attachmentEvents.count == 1)
      #expect(attachmentEvents.first?.payload.attachment?.path == attachment
        .path)
      #expect(try Data(contentsOf: consumer.sourceFile) == original)

      let withoutFix = try await consumer.run(
        "reportsWithoutFix",
        phase: "without-fix"
      )
      _ = try withoutFix.completedTestID(named: "reportsWithoutFix")

      #expect(try FileManager.default
        .contentsOfDirectory(atPath: withoutFix.attachments.path).isEmpty)
      #expect(try withoutFix.records()
        .allSatisfy { $0.payload.kind != "valueAttached" })
      #expect(try Data(contentsOf: consumer.sourceFile) == original)

      let reportsDirectory = consumer.root.appendingPathComponent(
        "collected",
        isDirectory: true
      )
      let session = SwiftTestingRuleSession(
        id: "report-process-session", directory: reportsDirectory.path,
        rootPath: consumer.root.path, isCorrection: true, sourceOnly: true
      )
      let collected = try await consumer.run(
        "reportsFix",
        phase: "collection",
        session: session
      )
      let testID = try collected.completedTestID(named: "reportsFix")
      let reportFiles = try FileManager.default.contentsOfDirectory(
        at: reportsDirectory, includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("report-") }

      #expect(reportFiles.count == 1)
      let report = try SwiftTestingRuleSession
        .readReport(at: #require(reportFiles.first))
      #expect(report.sessionID == "report-process-session")
      #expect(report.testID == testID)
      #expect(report.ruleID == "rename-class")
      #expect(report.enforcement == .advisory)
      #expect(report.baselineAccepted == [false])
      #expect(report.findings.violations.offenders.map(\.name) == ["Screen"])
      #expect(report.findings.violations.checkedCount == 1)
      try expectRename(
        report.findings.violations.fixes.compactMap(\.self),
        at: consumer.sourceFile.path
      )
      #expect(try FileManager.default
        .contentsOfDirectory(atPath: collected.attachments.path).isEmpty)
      #expect(try collected.records()
        .allSatisfy { $0.payload.kind != "valueAttached" })
      #expect(try Data(contentsOf: consumer.sourceFile) == original)

      let captureFiles = try FileManager.default.contentsOfDirectory(
        at: reportsDirectory.appendingPathComponent("captures"),
        includingPropertiesForKeys: nil
      )
      let captures = try captureFiles.map {
        try JSONDecoder().decode(
          SourceCapture.Record.self,
          from: Data(contentsOf: $0)
        )
      }
      let capture = try #require(captures.first {
        guard case let .sourceFiles(including, _, _, _) = $0.scope.selection
        else { return false }
        return including == ["Sources/App/**"]
      })
      #expect(capture.sessionID == "report-process-session")
      #expect(URL(fileURLWithPath: capture.scope.rootPath)
        .resolvingSymlinksInPath().path == consumer.root.path)
      let input = try #require(capture.inputs
        .first {
          URL(fileURLWithPath: $0.path).resolvingSymlinksInPath()
            == consumer.sourceFile
        })
      #expect(input
        .digest ==
        "095c8a9cf290bb1174a709ca806d070eaa57d8e148eae827219d2ce4aae33e81")
      try await SourceCapture.validate(captures)
    }

    private func expectRename(
      _ fixes: [SourceFix],
      at filePath: String,
      sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
      #expect(fixes.count == 1, sourceLocation: sourceLocation)
      let fix = try #require(fixes.first, sourceLocation: sourceLocation)
      #expect(fix.title == "Rename class", sourceLocation: sourceLocation)
      #expect(fix.edits.count == 1, sourceLocation: sourceLocation)
      let edit = try #require(fix.edits.first, sourceLocation: sourceLocation)
      #expect(
        URL(fileURLWithPath: edit.source.filePath).resolvingSymlinksInPath()
          == URL(fileURLWithPath: filePath).resolvingSymlinksInPath(),
        sourceLocation: sourceLocation
      )
      #expect(edit.source.range == 6..<12, sourceLocation: sourceLocation)
      #expect(edit.source.text == "Screen", sourceLocation: sourceLocation)
      #expect(
        Data(edit.source.file.text.utf8) == Data("class Screen {}\n".utf8),
        sourceLocation: sourceLocation
      )
      #expect(edit.replacement == "Updated", sourceLocation: sourceLocation)
    }
  }
#endif
