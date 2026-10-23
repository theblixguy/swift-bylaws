import BylawsCore
import Foundation

actor CorrectionIndexBuilds {
  private struct Pending: Sendable {
    let id = UUID()
    let task: Task<String, any Error>
  }

  private let directory: URL
  private let buildIndex: @Sendable (String, URL) async throws -> String
  private var paths: [String: String]
  private var pending: [String: Pending] = [:]

  init(
    directory: URL,
    testRun: SwiftPMTestRun?,
    buildIndex: @escaping @Sendable (String, URL) async throws -> String = {
      try await SwiftPMTestRunner.buildIndex(atRoot: $0, directory: $1)
    }
  ) {
    self.directory = directory
    self.buildIndex = buildIndex
    paths = if let testRun, let path = testRun.indexStorePath {
      [Self.key(testRun.packageRootPath): path]
    } else {
      [:]
    }
  }

  func buildIfNeeded(atRoot root: String) async throws -> String {
    try Task.checkCancellation()
    let key = Self.key(root)
    if let path = paths[key] { return path }
    let entry: Pending
    if let existing = pending[key] {
      entry = existing
    } else {
      guard FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: root)
          .appendingPathComponent("Package.swift").path
      ) else {
        throw CaptureError(
          "correction needs a fresh compiler index for '\(root)'; this run supports SwiftPM index builds"
        )
      }
      let output = directory.appendingPathComponent(UUID().uuidString)
      let buildIndex = buildIndex
      entry = Pending(task: Task { @concurrent in
        try await buildIndex(root, output)
      })
      pending[key] = entry
    }
    do {
      let path = try await withTaskCancellationHandler {
        let value = try await entry.task.value
        try Task.checkCancellation()
        return value
      } onCancel: {
        entry.task.cancel()
      }
      if pending[key]?.id == entry.id {
        pending[key] = nil
        paths[key] = path
      }
      return path
    } catch {
      if pending[key]?.id == entry.id {
        pending[key] = nil
      }
      throw error
    }
  }

  private static func key(_ root: String) -> String {
    URL(fileURLWithPath: root).resolvingSymlinksInPath().path
  }
}
