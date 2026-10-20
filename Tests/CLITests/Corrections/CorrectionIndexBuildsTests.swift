import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner

@Suite("Correction index build lifecycle", .timeLimit(.minutes(1)))
struct CorrectionIndexBuildsTests {
  @Test("Concurrent root aliases share build and completed path")
  func sharedBuild() async throws {
    let project = try TemporaryProject(files: [
      "First/Package.swift": "", "Second/Package.swift": "",
    ])
    let firstRoot = project.fileURL(for: "First").path
    let secondRoot = project.fileURL(for: "Second").path
    let firstPath = project.fileURL(for: "first-index").path
    let secondPath = project.fileURL(for: "second-index").path
    let control = BuildControl(laterPath: secondPath)
    let directory = project.fileURL(for: "builds")
    let builds = CorrectionIndexBuilds(
      directory: directory, testRun: nil, buildIndex: control.build
    )

    let paths = try await withThrowingTaskGroup(of: String.self) { group in
      for index in 0..<12 {
        let root = index.isMultiple(of: 2) ? firstRoot : firstRoot + "/."
        group.addTask { try await builds.buildIfNeeded(atRoot: root) }
      }
      await control.waitUntilStarted()
      await control.complete(.success(firstPath))
      var paths: [String] = []
      for try await path in group { paths.append(path) }
      return paths
    }

    #expect(paths.count == 12)
    #expect(paths.allSatisfy { $0 == firstPath })
    #expect(try await builds.buildIfNeeded(atRoot: firstRoot) == firstPath)
    #expect(await control.requests.count == 1)
    #expect(try await builds.buildIfNeeded(atRoot: secondRoot) == secondPath)
    let requests = await control.requests
    try #require(requests.count == 2)
    #expect(URL(fileURLWithPath: requests[0].root).standardizedFileURL
      .path == firstRoot)
    #expect(requests[1].root == secondRoot)
    #expect(requests
      .allSatisfy {
        $0.directory.deletingLastPathComponent().path == directory.path
      })
    #expect(requests[0].directory != requests[1].directory)
  }

  @Test("Failed build permits retry in new directory")
  func failureRetry() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let retryPath = project.fileURL(for: "retry-index").path
    let control = BuildControl(laterPath: retryPath)
    let builds = CorrectionIndexBuilds(
      directory: project.fileURL(for: "builds"), testRun: nil,
      buildIndex: control.build
    )
    let first = Task { @concurrent in
      try await builds.buildIfNeeded(atRoot: project.rootURL.path)
    }
    await control.waitUntilStarted()
    await control.complete(.failure(.failed))

    await #expect(throws: BuildFailure.failed) { try await first.value }
    #expect(try await builds
      .buildIfNeeded(atRoot: project.rootURL.path) == retryPath)
    #expect(try await builds
      .buildIfNeeded(atRoot: project.rootURL.path) == retryPath)
    let requests = await control.requests
    try #require(requests.count == 2)
    #expect(requests[0].directory != requests[1].directory)
  }

  @Test("Caller cancellation stops build and permits retry")
  func cancellationRetry() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let retryPath = project.fileURL(for: "retry-index").path
    let control = BuildControl(laterPath: retryPath)
    let builds = CorrectionIndexBuilds(
      directory: project.fileURL(for: "builds"), testRun: nil,
      buildIndex: control.build
    )
    let first = Task { @concurrent in
      try await builds.buildIfNeeded(atRoot: project.rootURL.path)
    }
    await control.waitUntilStarted()
    first.cancel()

    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(try await builds
      .buildIfNeeded(atRoot: project.rootURL.path) == retryPath)
    #expect(await control.requests.count == 2)
  }

  @Test("Cancelled caller skips build operation")
  func cancelledBeforeBuild() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let control = BuildControl(laterPath: "unused")
    let builds = CorrectionIndexBuilds(
      directory: project.fileURL(for: "builds"), testRun: nil,
      buildIndex: control.build
    )

    await withTaskGroup(of: Void.self) { group in
      group.cancelAll()
      group.addTask {
        await #expect(throws: CancellationError.self) {
          try await builds.buildIfNeeded(atRoot: project.rootURL.path)
        }
      }
    }

    #expect(await control.requests.isEmpty)
  }

  private enum BuildFailure: Error, Equatable {
    case failed
  }

  private actor BuildControl {
    private let laterPath: String
    private let results: AsyncStream<Result<String, BuildFailure>>
    private let completion: AsyncStream<Result<String, BuildFailure>>
      .Continuation
    private var start: CheckedContinuation<Void, Never>?
    private(set) var requests: [(root: String, directory: URL)] = []

    init(laterPath: String) {
      self.laterPath = laterPath
      (results, completion) = AsyncStream.makeStream()
    }

    func build(root: String, directory: URL) async throws -> String {
      requests.append((root, directory))
      start?.resume()
      start = nil
      guard requests.count == 1 else { return laterPath }
      let result = await results.first { _ in true }
      try Task.checkCancellation()
      guard let result else { throw BuildFailure.failed }
      return try result.get()
    }

    func waitUntilStarted() async {
      guard requests.isEmpty else { return }
      await withCheckedContinuation { start = $0 }
    }

    func complete(_ result: Result<String, BuildFailure>) {
      completion.yield(result)
      completion.finish()
    }
  }
}
