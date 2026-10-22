import BylawsTestSupport
import Foundation
import Subprocess
import Testing
@testable import BylawsRunner

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("SwiftPM command process", .timeLimit(.minutes(1)))
struct SwiftPMCommandTests {
  @Test("Arguments, environment and working directory retain their values")
  func commandInputs() async throws {
    let project = try project()
    let script = #"""
    printf '%s\n' "$PWD" "$MOCK_VALUE" "$#" "$1" "$2"
    printf 'build error\n' >&2
    exit 7
    """#
    var environment = environment(in: project)
    environment["MOCK_VALUE"] = "café and $HOME"

    let result = try await SwiftPMCommand.run(
      arguments: ["-c", script, "swift", "value with spaces", "$(literal)"],
      rootPath: project.rootURL.path,
      directory: project.rootURL,
      environment: environment
    )

    #expect(result.terminationStatus == .exited(7))
    let lines = String(decoding: result.standardOutput, as: UTF8.self)
      .split(separator: "\n", omittingEmptySubsequences: false)
    let currentDirectory = try #require(lines.first)
    #expect(URL(fileURLWithPath: String(currentDirectory))
      .resolvingSymlinksInPath().path == project.rootURL
      .resolvingSymlinksInPath().path)
    #expect(Array(lines.dropFirst()) == [
      "café and $HOME", "2", "value with spaces", "$(literal)", "",
    ])
    #expect(String(decoding: result.standardError, as: UTF8.self) ==
      "build error\n")
    #expect(throws: SwiftPMTestRunnerError.self) {
      try SwiftPMTestRunner.checkStatus(result)
    }
    #expect(try outputFiles(in: project).isEmpty)
  }

  @Test("Large stdout and stderr remain complete")
  func largeOutput() async throws {
    let project = try project()
    let script = """
    /bin/dd if=/dev/zero bs=4096 count=512 2>/dev/null
    /bin/dd if=/dev/zero bs=4096 count=512 >&2 2>/dev/null
    """

    let result = try await SwiftPMCommand.run(
      arguments: ["-c", script], rootPath: project.rootURL.path,
      directory: project.rootURL, environment: environment(in: project)
    )

    #expect(result.terminationStatus == .exited(0))
    #expect(result.standardOutput == Data(repeating: 0, count: 2 * 1024 * 1024))
    #expect(result.standardError == Data(repeating: 0, count: 2 * 1024 * 1024))
    #expect(try outputFiles(in: project).isEmpty)
  }

  @Test("Signal termination fails collection")
  func signalTermination() async throws {
    let project = try project()
    let result = try await SwiftPMCommand.run(
      arguments: ["-c", #"kill -TERM "$$""#], rootPath: project.rootURL.path,
      directory: project.rootURL, environment: environment(in: project)
    )

    #expect(result.terminationStatus == .signaled(SIGTERM))
    #expect(throws: SwiftPMTestRunnerError.processSignaled(
      SIGTERM,
      "swift -c kill -TERM \"$$\"\n"
    )) {
      try SwiftPMTestRunner.checkStatus(result)
    }
    #expect(try outputFiles(in: project).isEmpty)
  }

  @Test("Launch failure removes output files")
  func launchFailure() async throws {
    let project = try TemporaryProject(files: [:])
    await #expect(throws: (any Error).self) {
      try await SwiftPMCommand.run(
        arguments: [], rootPath: project.rootURL.path,
        directory: project.rootURL,
        environment: ["PATH": project.rootURL.path]
      )
    }
    #expect(try outputFiles(in: project).isEmpty)
  }

  @Test("Cancellation interrupts command")
  func cancellation() async throws {
    let project = try project()
    let (started, continuation) = AsyncStream<Int32>.makeStream()

    let parent = try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        defer { continuation.finish() }
        _ = try await SwiftPMCommand.run(
          arguments: ["-c", "exec /bin/sleep 60"],
          rootPath: project.rootURL.path,
          directory: project.rootURL, environment: environment(in: project),
          onStart: { continuation.yield($0) }
        )
      }
      defer { group.cancelAll() }
      let parent = try #require(await started.first { _ in true })
      group.cancelAll()
      await #expect(throws: CancellationError.self) {
        try await group.waitForAll()
      }
      return parent
    }

    let result = kill(parent, 0)
    let error = errno
    #expect(result == -1)
    #expect(error == ESRCH)
    #expect(try outputFiles(in: project).isEmpty)
  }

  @Test("Cancelled task skips command launch")
  func cancelledBeforeLaunch() async throws {
    let project = try project()
    await withTaskGroup(of: Void.self) { group in
      group.cancelAll()
      group.addTask {
        await #expect(throws: CancellationError.self) {
          try await SwiftPMCommand.run(
            arguments: ["-c", "printf launched > launched"],
            rootPath: project.rootURL.path,
            directory: project.rootURL, environment: environment(in: project)
          )
        }
      }
    }
    #expect(!FileManager.default
      .fileExists(atPath: project.fileURL(for: "launched").path))
    #expect(try outputFiles(in: project).isEmpty)
  }

  private func project() throws -> TemporaryProject {
    let project = try TemporaryProject(files: [:])
    try FileManager.default.createDirectory(
      at: project.fileURL(for: "bin"), withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: project.fileURL(for: "bin/swift"),
      withDestinationURL: URL(fileURLWithPath: "/bin/sh")
    )
    return project
  }

  private func environment(in project: TemporaryProject) -> [String: String] {
    ["PATH": project.fileURL(for: "bin").path]
  }

  private func outputFiles(in project: TemporaryProject) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: project.rootURL.path)
      .filter { $0.hasPrefix("stdout-") || $0.hasPrefix("stderr-") }
  }
}
