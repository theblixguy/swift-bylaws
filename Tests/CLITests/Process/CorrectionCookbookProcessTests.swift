#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsSemantics
  import BylawsTestSupport
  import Foundation
  import Subprocess
  import Testing

  @Suite("Compiled correction cookbook")
  struct CorrectionCookbookProcessTests {
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

      for mock in CorrectionCookbookMock.cases {
        let recipes = blocks.filter {
          $0.contains("report(ruleID: \"\(mock.ruleID)\"")
        }
        try #require(recipes.count == 1)
        let recipe = try #require(recipes.first)
        let declaration = try #require(recipe.components(separatedBy: "\n")
          .first { $0.hasPrefix("func ") })
        let function = try #require(declaration.dropFirst(5)
          .split(separator: "(").first).description
        for (path, source) in mock.sources {
          let file = consumer.root.appendingPathComponent(path)
          try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try source.write(to: file, atomically: true, encoding: .utf8)
        }
        let initial = try await collectedReport(
          consumer, function: function, ruleID: mock.ruleID,
          phase: "\(mock.ruleID)-before"
        )
        try #require(!initial.findings.violations.isEmpty)
        let edits = initial.findings.violations.fixes.compactMap(\.self)
          .flatMap(\.edits)
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
            try first.source.file.replacement(applying: fileEdits).replacement
          } else {
            original
          }
          #expect(
            Data(actual.utf8) == Data(expected.utf8),
            "\(mock.ruleID): \(path)"
          )
          try actual.write(to: file, atomically: true, encoding: .utf8)
        }
        let verified = try await collectedReport(
          consumer, function: function, ruleID: mock.ruleID,
          phase: "\(mock.ruleID)-after"
        )
        #expect(verified.findings.violations.isEmpty)
        #expect(verified.findings.violations.fixes.compactMap(\.self).isEmpty)
        #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
        for path in mock.sources.keys {
          try FileManager.default.removeItem(
            at: consumer.root.appendingPathComponent(path)
          )
        }
      }
    }

    private func collectedReport(
      _ consumer: SwiftTestingReportConsumer,
      function: String,
      ruleID: String,
      phase: String
    ) async throws -> SwiftTestingRuleReport {
      let directory = consumer.root.appendingPathComponent(
        phase, isDirectory: true
      )
      let session = SwiftTestingRuleSession(
        id: phase, directory: directory.path,
        rootPath: consumer.root.path, isCorrection: true, sourceOnly: true
      )
      let result = try await consumer.run(
        function, phase: "\(phase)-test", session: session
      )
      let testID = try result.completedTestID(named: function)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      ).filter { $0.lastPathComponent.hasPrefix("report-") }
      try #require(files.count == 1)
      let report = try SwiftTestingRuleSession.readReport(
        at: #require(files.first)
      )
      #expect(report.sessionID == phase)
      #expect(report.ruleID.rawValue == ruleID)
      #expect(report.testID == testID)
      return report
    }
  }
#endif
