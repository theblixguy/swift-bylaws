#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsSemantics
  import BylawsTestSupport
  import Foundation
  import Subprocess
  import Testing

  @Suite("Compiled correction cookbook")
  struct CorrectionCookbookProcessTests {
    @Test("Portable formatting recipes correct together and pass second run")
    func portableFormattingLifecycle() throws {
      let project = try CLIProcessProject(source: "", rules: nil)
      var previousPaths: Set<String> = []
      for mock in CorrectionCookbookMock.formattingCases {
        try mock.bylawsSource().write(
          to: project.root.appendingPathComponent("Bylaws.swift"),
          atomically: true, encoding: .utf8
        )
        for path in previousPaths.subtracting(mock.sources.keys) {
          try FileManager.default
            .removeItem(at: project.root.appendingPathComponent(path))
        }
        for (path, source) in mock.sources {
          let file = project.root.appendingPathComponent(path)
          try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try source.write(to: file, atomically: true, encoding: .utf8)
        }
        previousPaths = Set(mock.sources.keys)

        let correction = try project.run(
          "--autocorrect", "--source-only", "--skip-tests", "--format", "json"
        )

        try #require(
          correction.status == 0,
          "\(mock.testDescription)\n\(correction.standardError)"
        )
        #expect(correction.standardError.contains("Corrected 1 file:"))
        for (path, expected) in mock.expected {
          #expect(try String(
            contentsOf: project.root.appendingPathComponent(path),
            encoding: .utf8
          ) == expected, "\(mock.testDescription)")
        }

        let repeated = try project.run(
          "--source-only", "--skip-tests", "--format", "json"
        )

        #expect(
          repeated.status == 0,
          "\(mock.testDescription)\n\(repeated.standardError)"
        )
        for result in [correction, repeated] {
          let report = try #require(JSONSerialization.jsonObject(
            with: Data(result.standardOutput.utf8)
          ) as? [String: Any])
          let summary = try #require(report["summary"] as? [String: Int])
          let rules = try #require(report["rules"] as? [[String: Any]])
          #expect(summary["checkedRules"] == 3)
          #expect(summary["violations"] == 0)
          #expect(Set(rules.compactMap { $0["id"] as? String }) ==
            Set(mock.ruleIDs))
        }
        for (path, expected) in mock.expected {
          #expect(try String(
            contentsOf: project.root.appendingPathComponent(path),
            encoding: .utf8
          ) == expected, "\(mock.testDescription)")
        }
      }
    }

    @Test(
      "Native recipes correct source and pass on second run",
      .timeLimit(.minutes(10))
    )
    func nativeRecipes() async throws {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      var blocks: [String] = []
      for article in ["CorrectingSourceCookbook", "FormattingCookbook"] {
        let path = root.appendingPathComponent(
          "Sources/Bylaws/Bylaws.docc/\(article).md"
        )
        let source = try String(contentsOf: path, encoding: .utf8)
        blocks += source.components(separatedBy: "```swift\n").dropFirst()
          .compactMap { $0.components(separatedBy: "\n```").first }
          .filter { $0.contains("import Testing") }
      }
      try #require(blocks.count == 13)
      let functions: [String] = blocks.flatMap { block in
        block.components(separatedBy: "\n").compactMap { line in
          line.hasPrefix("func ") ? line.dropFirst(5).split(separator: "(")
            .first.map(String.init) : nil
        }
      }
      try #require(functions.count == 13)
      let consumer = try SwiftTestingReportConsumer(
        additionalTests: blocks.joined(separator: "\n\n")
      )
      let result = try await consumer.run(
        functions.joined(separator: "|"), phase: "cookbook"
      )
      try #require(result.status == .exited(0), "\(result.output)")
      let records = try result.records()
      let completed = records.filter {
        $0.kind == "event" && $0.payload.kind == "testEnded"
      }.compactMap(\.payload.testID)

      #expect(completed.count == 13)
      #expect(records.last?.payload.kind == "runEnded")
      for function in functions {
        #expect(completed.contains { $0.contains(function) }, "\(function)")
      }

      let testFile = consumer.root
        .appendingPathComponent("Tests/RuleTests/Rules.swift")
      let originalTests = try String(contentsOf: testFile, encoding: .utf8)
      let cases = CorrectionCookbookMock.cases + CorrectionCookbookMock
        .formattingCases
      for (index, mock) in cases.enumerated() {
        let functions = try mock.swiftTestingFunctions()
        let configuredTests = originalTests.replacing(
          "maximumWidth: Int? = nil",
          with: "maximumWidth: Int? = \(mock.maximumWidth.map(String.init) ?? "nil")"
        )
        if try String(contentsOf: testFile, encoding: .utf8) !=
          configuredTests
        {
          try configuredTests.write(
            to: testFile,
            atomically: true,
            encoding: .utf8
          )
        }
        for (path, source) in mock.sources {
          let file = consumer.root.appendingPathComponent(path)
          try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try source.write(to: file, atomically: true, encoding: .utf8)
        }
        let initial = try await collectedReports(
          consumer, functions: functions, ruleIDs: mock.ruleIDs,
          phase: "recipe-\(index)-before"
        )
        try #require(initial.allSatisfy { !$0.findings.violations.isEmpty })
        let edits = initial.flatMap(\.findings.violations.fixes)
          .compactMap(\.self).flatMap(\.edits)
        let candidates = initial.flatMap(\.findings.violations.layoutCandidates)
        try #require(!edits.isEmpty)
        let paths = Set(mock.expected.keys.map {
          consumer.root.appendingPathComponent($0).resolvingSymlinksInPath()
        })
        #expect(Set(edits.map {
          URL(fileURLWithPath: $0.source.filePath).resolvingSymlinksInPath()
        }).isSubset(of: paths))
        for (path, expected) in mock.expected {
          let original = try #require(mock.sources[path])
          let file = consumer.root.appendingPathComponent(path)
            .resolvingSymlinksInPath()
          let fileEdits = edits.filter {
            URL(fileURLWithPath: $0.source.filePath).resolvingSymlinksInPath()
              == file
          }
          if let first = fileEdits.first {
            #expect(Data(first.source.file.text.utf8) == Data(original.utf8))
          }
          let actual = if let first = fileEdits.first {
            try first.source.file.replacement(
              applying: fileEdits,
              layoutCandidates: candidates.filter {
                URL(fileURLWithPath: $0.source.filePath)
                  .resolvingSymlinksInPath()
                  == file
              }
            ).replacement
          } else {
            original
          }
          #expect(
            Data(actual.utf8) == Data(expected.utf8),
            "\(mock.testDescription): \(path)"
          )
          try actual.write(to: file, atomically: true, encoding: .utf8)
        }
        let verified = try await collectedReports(
          consumer, functions: functions, ruleIDs: mock.ruleIDs,
          phase: "recipe-\(index)-after"
        )
        for report in verified {
          #expect(report.findings.violations.isEmpty, "\(report.ruleID)")
          #expect(
            report.findings.violations.fixes.compactMap(\.self).isEmpty,
            "\(report.ruleID)"
          )
        }
        #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
        for path in mock.sources.keys {
          try FileManager.default.removeItem(
            at: consumer.root.appendingPathComponent(path)
          )
        }
      }
    }

    private func collectedReports(
      _ consumer: SwiftTestingReportConsumer,
      functions: [String],
      ruleIDs: [String],
      phase: String
    ) async throws -> [SwiftTestingRuleReport] {
      let directory = consumer.root.appendingPathComponent(
        phase, isDirectory: true
      )
      let session = SwiftTestingRuleSession(
        id: phase, directory: directory.path,
        rootPath: consumer.root.path, isCorrection: true, sourceOnly: true
      )
      let result = try await consumer.run(
        functions.joined(separator: "|"), phase: "\(phase)-test",
        session: session
      )
      try #require(result.status == .exited(0), "\(result.output)")
      let records = try result.records()
      let testIDs = records.filter {
        $0.kind == "event" && $0.payload.kind == "testEnded"
      }.compactMap(\.payload.testID)
      #expect(testIDs.count == functions.count)
      #expect(records.last?.payload.kind == "runEnded")
      for function in functions {
        #expect(testIDs.contains { $0.contains(function) }, "\(function)")
      }
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("report-") }
      try #require(files.count == ruleIDs.count)
      let reports = try files.map(SwiftTestingRuleSession.readReport)
      #expect(Set(reports.map(\.ruleID.rawValue)) == Set(ruleIDs))
      for report in reports {
        #expect(report.sessionID == phase)
        #expect(testIDs.contains(report.testID))
      }
      return reports
    }
  }
#endif
