#if os(macOS) || os(Linux)
  import BylawsCore
  import BylawsTestSupport
  import Foundation
  import Subprocess
  import Testing

  struct SwiftTestingReportConsumer: Sendable {
    static let source = "class Screen {}\n"
    private let project: TemporaryProject

    var root: URL { project.rootURL.resolvingSymlinksInPath() }
    var sourceFile: URL {
      root.appendingPathComponent("Sources/App/Screen.swift")
    }

    init() throws {
      let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
      project = try TemporaryProject(files: [
        "Package.swift": """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
          name: "ReportingConsumer",
          platforms: [.macOS(.v14)],
          dependencies: [.package(path: \(String(reflecting: repository.path)), traits: [])],
          targets: [
            .target(name: "App"),
            .testTarget(name: "RuleTests", dependencies: [
              "App",
              .product(name: "Bylaws", package: \(String(reflecting: repository.lastPathComponent.lowercased())))
            ])
          ]
        )
        """,
        "Sources/App/Screen.swift": Self.source,
        "Tests/RuleTests/Rules.swift": #"""
        import Bylaws
        import Testing

        private let app = Codebase(
          root: .automatic(above: #filePath),
          including: ["Sources/App/**"], swiftLanguageMode: .v6
        )

        @Test func reportsFix() async throws {
          let violations = try await app.classes.violations(of: .named("Updated"))
            .withFix("Rename class") { context in
              try context.offender.nameSource.replacement(with: "Updated")
            }
          violations.report(ruleID: "rename-class", enforcement: .advisory)
        }

        @Test func reportsWithoutFix() async throws {
          let violations = try await app.classes.violations(of: .named("Updated"))
          violations.report(ruleID: "rename-class", enforcement: .advisory)
        }
        """#,
      ])
    }

    @concurrent
    func run(
      _ function: String,
      phase: String,
      session: SwiftTestingRuleSession? = nil
    ) async throws -> Result {
      try Task.checkCancellation()
      let directory = root.appendingPathComponent(phase, isDirectory: true)
      let attachments = directory.appendingPathComponent(
        "attachments",
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: attachments,
        withIntermediateDirectories: true
      )
      let events = directory.appendingPathComponent("events.jsonl")
      var environment = Environment.inherit.updating([
        "BYLAWS_SWIFT_TESTING_RULE_SESSION": nil,
        "BYLAWS_SOURCE_CAPTURE_DIRECTORY": nil,
        "BYLAWS_SOURCE_CAPTURE_ID": nil,
        "BYLAWS_INDEX_STORE": nil,
        "BYLAWS_FRESH_INDEX_STORE": nil,
        "BYLAWS_FRESH_INDEX_ROOT": nil,
        "BYLAWS_CORRECTION_ACTIVE": nil,
        "BYLAWS_SOURCE_ONLY": nil,
      ])
      if let session {
        let request = directory.appendingPathComponent("request.json")
        let captures = URL(fileURLWithPath: session.directory)
          .appendingPathComponent("captures", isDirectory: true)
        try FileManager.default.createDirectory(
          at: captures,
          withIntermediateDirectories: true
        )
        try JSONEncoder().encode(session).write(to: request)
        environment = environment.updating([
          "BYLAWS_SWIFT_TESTING_RULE_SESSION": request.path,
          "BYLAWS_SOURCE_CAPTURE_DIRECTORY": captures.path,
          "BYLAWS_SOURCE_CAPTURE_ID": session.id,
          "BYLAWS_CORRECTION_ACTIVE": session.isCorrection ? "1" : nil,
          "BYLAWS_SOURCE_ONLY": session.sourceOnly ? "1" : nil,
        ])
      }
      var options = PlatformOptions()
      options.processGroupID = 0
      // Graceful teardown can stop escalation before compiler children exit.
      options.teardownSequence = [
        .send(
          signal: .kill,
          toProcessGroup: true,
          allowedDurationToNextStep: .zero
        ),
      ]
      let result = try await Subprocess.run(
        .name("swift"),
        arguments: Arguments([
          "test", "--disable-sandbox", "--package-path", root.path,
          "--filter", function, "--attachments-path", attachments.path,
          "--event-stream-version", "0", "--event-stream-output-path",
          events.path,
        ]),
        environment: environment, platformOptions: options,
        output: .string(limit: 8 * 1024 * 1024),
        error: .string(limit: 8 * 1024 * 1024)
      )
      try Task.checkCancellation()
      return Result(
        status: result.terminationStatus,
        output: result.standardOutput + result.standardError,
        attachments: attachments, events: events
      )
    }

    struct Result: Sendable {
      let status: TerminationStatus
      let output: String
      let attachments: URL
      let events: URL

      func records() throws -> [Record] {
        let decoder = JSONDecoder()
        return try Data(contentsOf: events).split(separator: 0x0A).map {
          try decoder.decode(Record.self, from: Data($0))
        }
      }

      func completedTestID(
        named function: String,
        sourceLocation: SourceLocation = #_sourceLocation
      ) throws -> String {
        try #require(
          status == .exited(0),
          "\(status)\n\(output)",
          sourceLocation: sourceLocation
        )
        let records = try records()
        #expect(
          records.allSatisfy { $0.version == 0 },
          sourceLocation: sourceLocation
        )
        #expect(
          records.last?.payload.kind == "runEnded",
          sourceLocation: sourceLocation
        )
        let completed = records
          .filter { $0.kind == "event" && $0.payload.kind == "testEnded" }
        #expect(completed.count == 1, sourceLocation: sourceLocation)
        let id = try #require(
          completed.first?.payload.testID,
          sourceLocation: sourceLocation
        )
        #expect(id.contains(function), sourceLocation: sourceLocation)
        return id
      }
    }

    struct Record: Decodable {
      let version: Int
      let kind: String
      let payload: Payload

      struct Payload: Decodable {
        let kind: String?
        let testID: String?
        let attachment: Attachment?
      }

      struct Attachment: Decodable {
        let path: String
      }
    }
  }
#endif
