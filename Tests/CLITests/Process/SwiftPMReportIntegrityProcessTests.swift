#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsRunner
  import BylawsTestSupport
  import Foundation
  import Testing

  @Suite("SwiftPM report integrity")
  struct SwiftPMReportIntegrityProcessTests {
    @Test(
      "Child output corruption blocks collection and identifies malformed file",
      .timeLimit(.minutes(10))
    )
    func corruptedOutput() async throws {
      let consumer = try SwiftTestingReportConsumer(
        enforcement: .enforced,
        additionalTests: Self.corruptingTests
      )
      for corruption in Corruption.allCases {
        let directory = consumer.root
          .appendingPathComponent(
            ".build/bylaws-reporting-\(corruption.rawValue)"
          )
        let session = SwiftTestingRuleSession(
          id: corruption.rawValue,
          directory: directory.path,
          rootPath: consumer.root.path,
          isCorrection: true,
          sourceOnly: true
        )

        await #expect {
          try await SwiftPMTestRunner.collect(
            atRoot: consumer.root.path,
            filters: [corruption.rawValue],
            swiftPMArguments: ["--disable-sandbox"],
            session: session
          )
        } throws: { error in
          guard let error = error as? SwiftPMTestRunnerError
          else { return false }
          switch corruption {
          case .reportsUnstartedTest:
            return error == .mismatchedReport
          case .reportsForeignCapture:
            return error == .mismatchedCapture
          case .reportsMalformedReport, .reportsMalformedCapture,
               .reportsMalformedEvents:
            guard case let .cannotReadOutput(path, reason) = error else {
              return false
            }
            let expected = switch corruption {
            case .reportsMalformedReport:
              directory.appendingPathComponent("report-malformed.json")
            case .reportsMalformedCapture:
              directory
                .appendingPathComponent("captures/capture-malformed.json")
            case .reportsMalformedEvents:
              directory.appendingPathComponent("events.jsonl")
            default:
              directory
            }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
              == expected.resolvingSymlinksInPath() && !reason.isEmpty
          }
        }

        let reportFiles = try FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil
        ).filter {
          $0.lastPathComponent.hasPrefix("report-")
            && $0.lastPathComponent != "report-malformed.json"
        }
        #expect(reportFiles.count == 1)
        let report = try SwiftTestingRuleSession.readReport(
          at: #require(reportFiles.first)
        )
        #expect(report.sessionID == session.id)
        #expect(report.ruleID == "rename-class")
        #expect(report.findings.violations.offenders.map(\.name) == ["Screen"])
        #expect(try Data(contentsOf: consumer.sourceFile)
          == Data("class Screen {}\n".utf8))
      }
    }

    private enum Corruption: String, CaseIterable, Sendable {
      case reportsUnstartedTest
      case reportsForeignCapture
      case reportsMalformedReport
      case reportsMalformedCapture
      case reportsMalformedEvents
    }

    private static let corruptingTests = #"""
    import Foundation

    private func outputDirectory() throws -> URL {
      let requestPath = try #require(
        ProcessInfo.processInfo.environment["BYLAWS_SWIFT_TESTING_RULE_SESSION"]
      )
      let request = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: requestPath))
      ) as? [String: Any])
      return URL(fileURLWithPath: try #require(request["directory"] as? String))
    }

    private func outputFile(in directory: URL, prefix: String) throws -> URL {
      let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
      )
      return try #require(files.first {
        $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json"
      })
    }

    @Test func reportsUnstartedTest() async throws {
      try await reportRename()
      let file = try outputFile(in: outputDirectory(), prefix: "report-")
      var report = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: file)
      ) as? [String: Any])
      report["testID"] = "RuleTests/unstartedTest()"
      try JSONSerialization.data(withJSONObject: report).write(to: file)
    }

    @Test func reportsForeignCapture() async throws {
      try await reportRename()
      let directory = try outputDirectory().appendingPathComponent("captures")
      let file = try outputFile(in: directory, prefix: "")
      var capture = try #require(JSONSerialization.jsonObject(
        with: Data(contentsOf: file)
      ) as? [String: Any])
      capture["sessionID"] = "another-session"
      try JSONSerialization.data(withJSONObject: capture).write(to: file)
    }

    @Test func reportsMalformedReport() async throws {
      try await reportRename()
      let directory = try outputDirectory()
      _ = try outputFile(in: directory, prefix: "report-")
      try Data("malformed report".utf8).write(
        to: directory.appendingPathComponent("report-malformed.json")
      )
    }

    @Test func reportsMalformedEvents() async throws {
      try await reportRename()
      let file = try outputDirectory().appendingPathComponent("events.jsonl")
      try #require(!Data(contentsOf: file).isEmpty)
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.write(contentsOf: Data("x".utf8))
    }

    @Test func reportsMalformedCapture() async throws {
      try await reportRename()
      let directory = try outputDirectory().appendingPathComponent("captures")
      _ = try outputFile(in: directory, prefix: "")
      try Data("malformed capture".utf8).write(
        to: directory.appendingPathComponent("capture-malformed.json")
      )
    }
    """#
  }
#endif
