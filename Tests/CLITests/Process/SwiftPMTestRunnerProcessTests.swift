import BylawsCore
import BylawsTestSupport
import Foundation
import Subprocess
import Testing
@testable import BylawsRunner

@Suite("SwiftPM test runner")
struct SwiftPMTestRunnerProcessTests {
  @Test(
    "Child environment clears correction state and retains unrelated values"
  )
  func childEnvironment() {
    let correctionKeys = [
      SwiftTestingRuleSession.environmentKey, "BYLAWS_SOURCE_CAPTURE_DIRECTORY",
      "BYLAWS_SOURCE_CAPTURE_ID", "BYLAWS_FRESH_INDEX_STORE",
      "BYLAWS_FRESH_INDEX_ROOT", "BYLAWS_CORRECTION_ACTIVE",
      "BYLAWS_SOURCE_ONLY",
    ]
    var inherited = Dictionary(uniqueKeysWithValues: correctionKeys.map { (
      $0,
      "old"
    ) })
    inherited["BYLAWS_INDEX_STORE"] = "/existing/index"
    inherited["PATH"] = "/usr/bin"

    #expect(SwiftPMTestRunner.subprocessEnvironment(inherited) == [
      "BYLAWS_INDEX_STORE": "/existing/index", "PATH": "/usr/bin",
    ])
  }

  @Test("Malformed metadata names command and package root", arguments: [
    "describe", "show-dependencies",
  ])
  func malformedMetadata(_ operation: String) {
    let result = SwiftPMCommand.Result(
      terminationStatus: .exited(0), arguments: ["package", operation],
      standardOutput: Data("malformed metadata".utf8), standardError: Data()
    )

    #expect {
      try SwiftPMTestRunner.decodeOutput(
        [String: String].self, from: result, atRoot: "/project"
      )
    } throws: { error in
      guard let error = error as? SwiftPMTestRunnerError,
            case let .cannotReadCommandOutput(command, root, reason) = error
      else { return false }
      return command == "swift package " + operation
        && root == "/project" && reason.contains("dataCorrupted")
    }
  }

  @Test("Empty parameter cases retain matched function")
  func emptyParameterCases() async throws {
    let project = try project(source: """
    import Testing

    @Test(arguments: [Int]())
    func holds(_ value: Int) {}
    """)
    let editProject = try TemporaryProject(files: ["App.swift": "class App {}"])
    let session = try session(in: project, rootPath: editProject.rootURL.path)

    let run = try await SwiftPMTestRunner.collect(
      atRoot: project.rootURL.path,
      filters: ["holds"],
      swiftPMArguments: ["--disable-sandbox"],
      session: session
    )

    let summary = try readSummary(in: session)
    #expect(summary.tests
      .contains { $0.kind == "function" && $0.name == "holds(_:)" })
    #expect(summary.caseCount == 0)
    #expect(summary.caseCounts.values.allSatisfy { $0 == 0 })
    let function = try #require(summary.tests.first { $0.name == "holds(_:)" })
    #expect(summary.caseCounts[function.id] == nil)
    #expect(summary.skippedTestIDs.contains(function.id))
    #expect(run.reports.isEmpty)
    #expect(run.captures.contains { record in
      record.inputs
        .contains { $0.path.hasSuffix("Tests/MockTests/Rules.swift") }
    })
    #expect(run
      .protectedSourcePaths ==
      [project.fileURL(for: "Tests/MockTests/Rules.swift").path])
    #expect(run.indexStorePath == nil)
    #expect(run.packageRootPath != session.rootPath)
  }

  @Test("Fresh index uses separate build and captures remain current")
  func freshCompilerIndex() async throws {
    let project = try project(source: """
    import Foundation
    import Testing

    @Test func holds() {
      #expect(ProcessInfo.processInfo.environment["BYLAWS_CORRECTION_ACTIVE"] == "1")
      #expect(ProcessInfo.processInfo.environment["BYLAWS_SOURCE_ONLY"] == nil)
    }
    @Test(.disabled()) func skipped() {}
    """)
    let session = try session(in: project, isCorrection: true)

    let run = try await SwiftPMTestRunner.collect(
      atRoot: project.rootURL.path, freshIndex: true,
      swiftPMArguments: ["--disable-sandbox"], session: session
    )

    let path = try #require(run.indexStorePath)
    #expect(path.hasPrefix(session.directory + "/build/"))
    #expect(FileManager.default.fileExists(atPath: path + "/v5"))
    #expect(run.packageRootPath == project.rootURL.path)
    let summary = try readSummary(in: session)
    let skipped = try #require(summary.tests.first { $0.name == "skipped()" })
    #expect(summary.skippedTestIDs.contains(skipped.id))
    #expect(summary.caseCounts[skipped.id] == nil)
    try await SourceCapture.validate(run.captures)
  }

  @Test("External package builds fresh index without test targets")
  func externalSourcePackage() async throws {
    let helper = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription
      let package = Package(
        name: "Helper", products: [.library(name: "Helper", targets: ["Helper"])],
        targets: [.target(name: "Helper")]
      )
      """,
      "Sources/Helper/Helper.swift": "public struct Helper {}",
    ])
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "SwiftPMBuildMock",
        dependencies: [.package(path: "\(helper.rootURL.path)")],
        targets: [.target(name: "App", dependencies: [
          .product(name: "Helper", package: "\(helper.rootURL.lastPathComponent.lowercased())")
        ])]
      )
      """,
      "Sources/App/App.swift": "import Helper; public struct App {}",
    ])
    let collector = SourceCapture.Collector()
    let directory = project.fileURL(for: "index-build")
    let path = try await SourceCapture.$collector.withValue(collector) {
      try await SwiftPMTestRunner.buildIndex(
        atRoot: project.rootURL.path, directory: directory,
        swiftPMArguments: ["--disable-sandbox"]
      )
    }
    #expect(FileManager.default.fileExists(atPath: path + "/v5"))
    let captures = await collector.captured
    #expect(captures.count == 2)
    #expect(captures.contains {
      $0.scope.rootPath == helper.rootURL.resolvingSymlinksInPath().path
    })
    try await SourceCapture.validate(captures)
    try "public struct ChangedHelper {}".write(
      to: helper.fileURL(for: "Sources/Helper/Helper.swift"),
      atomically: true, encoding: .utf8
    )
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(captures)
    }
  }

  @Test("Filter with no matching function fails collection")
  func missingFunction() async throws {
    let project = try project(source: """
    import Testing

    @Test func holds() {}
    """)
    let session = try session(in: project)

    await #expect(throws: SwiftPMTestRunnerError.noMatchingTests) {
      try await SwiftPMTestRunner.collect(
        atRoot: project.rootURL.path,
        filters: ["DoesNotExist"],
        swiftPMArguments: ["--disable-sandbox"],
        session: session
      )
    }
  }

  @Test("XCTest failure blocks collection")
  func xctestFailure() async throws {
    let project = try project(source: """
    import Testing
    import XCTest

    @Test func holds() {}

    final class FailingTests: XCTestCase {
      func testFailure() {
        XCTFail("Unrelated test failure")
      }
    }
    """)
    let session = try session(in: project)

    await #expect {
      try await SwiftPMTestRunner.collect(
        atRoot: project.rootURL.path,
        swiftPMArguments: ["--disable-sandbox"],
        session: session
      )
    } throws: { error in
      guard let failure = error as? SwiftPMTestRunnerError,
            case .processFailed = failure
      else {
        return false
      }
      return true
    }
  }

  private func readSummary(in session: SwiftTestingRuleSession) throws
    -> SwiftTestingRunSummary
  {
    try SwiftTestingRunSummary(
      data: Data(contentsOf: URL(fileURLWithPath: session.directory)
        .appendingPathComponent("events.jsonl")),
      requiresMatchingTests: false
    )
  }

  private func project(source: String) throws -> TemporaryProject {
    try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "TestRunnerMock",
        targets: [.testTarget(name: "MockTests")]
      )
      """,
      "Tests/MockTests/Rules.swift": source,
    ])
  }

  private func session(
    in project: TemporaryProject, rootPath: String? = nil,
    isCorrection: Bool = false
  ) throws
    -> SwiftTestingRuleSession
  {
    let directory = project.fileURL(for: "test-results")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true
    )
    return SwiftTestingRuleSession(
      id: UUID().uuidString, directory: directory.path,
      rootPath: rootPath ?? project.rootURL.path, isCorrection: isCorrection
    )
  }
}
