import BylawsCore
package import Foundation

extension SwiftPMTestRunner {
  @concurrent
  package static func buildIndex(
    atRoot rootPath: String,
    directory: URL,
    swiftPMArguments: [String] = []
  ) async throws -> String {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let scratch = directory.appendingPathComponent("build", isDirectory: true)
    var environment = subprocessEnvironment()
    let index = try await prepareIndexBuild(
      freshIndex: true, scratch: scratch, rootPath: rootPath,
      directory: directory, swiftPMArguments: swiftPMArguments,
      environment: environment
    )
    try await resolvePackage(
      atRoot: rootPath, directory: directory,
      swiftPMArguments: swiftPMArguments + index.arguments,
      environment: environment
    )
    let captures = try await captureInputs(
      atRoot: rootPath, directory: directory, scratch: scratch,
      swiftPMArguments: swiftPMArguments + index.arguments,
      environment: environment,
      sessionID: nil
    )

    environment["BYLAWS_CORRECTION_ACTIVE"] = "1"
    let result = try await SwiftPMCommand.run(
      arguments: ["build"] + swiftPMArguments + index.arguments
        + ["--package-path", rootPath],
      rootPath: rootPath, directory: directory, environment: environment
    )
    try checkStatus(result)
    try await SourceCapture.validate(captures)
    for capture in captures { try await SourceCapture.store(capture) }
    guard let path = index.storePath
    else { throw SwiftPMTestRunnerError.cannotLocateIndex }
    return path
  }

  struct IndexBuildConfiguration: Sendable {
    let arguments: [String]
    let storePath: String?
  }

  @concurrent
  static func prepareIndexBuild(
    freshIndex: Bool,
    scratch: URL,
    rootPath: String,
    directory: URL,
    swiftPMArguments: [String],
    environment: [String: String]
  ) async throws -> IndexBuildConfiguration {
    guard freshIndex else { return IndexBuildConfiguration(
      arguments: [],
      storePath: nil
    ) }
    guard !FileManager.default.fileExists(atPath: scratch.path) else {
      throw SwiftPMTestRunnerError.reusedIndexDirectory
    }
    let arguments = ["--scratch-path", scratch.path, "--enable-index-store"]
    let result = try await SwiftPMCommand.run(
      arguments: ["build"] + swiftPMArguments + arguments
        + ["--package-path", rootPath, "--show-bin-path"],
      rootPath: rootPath, directory: directory, environment: environment
    )
    try checkStatus(result)
    let binPath = String(decoding: result.standardOutput, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard binPath.hasPrefix("/"), !binPath.contains("\n") else {
      throw SwiftPMTestRunnerError.cannotLocateIndex
    }
    return IndexBuildConfiguration(
      arguments: arguments,
      storePath: URL(fileURLWithPath: binPath)
        .appendingPathComponent("index/store", isDirectory: true).path
    )
  }
}
