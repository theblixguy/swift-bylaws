import Foundation
import Subprocess

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

enum SwiftPMCommand {
  struct Result: Sendable {
    let terminationStatus: TerminationStatus
    let arguments: [String]
    let standardOutput: Data
    let standardError: Data
  }

  @concurrent
  static func run(
    arguments: [String],
    rootPath: String,
    directory: URL,
    environment: [String: String],
    onStart: (@Sendable (Int32) -> Void)? = nil
  ) async throws -> Result {
    try Task.checkCancellation()
    let id = UUID().uuidString
    let output = directory.appendingPathComponent("stdout-\(id)")
    let errors = directory.appendingPathComponent("stderr-\(id)")
    defer {
      try? FileManager.default.removeItem(at: output)
      try? FileManager.default.removeItem(at: errors)
    }
    let outputDescriptor = try FileDescriptor.open(
      FilePath(output.path), .writeOnly,
      options: [.create, .exclusiveCreate, .closeOnExec],
      permissions: [.ownerReadWrite]
    )
    defer { try? outputDescriptor.close() }
    let errorDescriptor = try FileDescriptor.open(
      FilePath(errors.path), .writeOnly,
      options: [.create, .exclusiveCreate, .closeOnExec],
      permissions: [.ownerReadWrite]
    )
    defer { try? errorDescriptor.close() }
    var options = PlatformOptions()
    // SwiftPM allows 30 seconds to cancel jobs in separate process groups.
    options.teardownSequence = [
      .send(
        signal: .interrupt, toProcessGroup: false,
        allowedDurationToNextStep: .seconds(35)
      ),
    ]
    let result = try await Subprocess.run(
      .name("swift"),
      arguments: Arguments(arguments),
      environment: .custom(
        Dictionary(
          uniqueKeysWithValues: environment.map {
            (Environment.Key(stringLiteral: $0.key), $0.value)
          }
        )
      ),
      workingDirectory: FilePath(rootPath),
      platformOptions: options,
      input: .none,
      output: .fileDescriptor(
        outputDescriptor,
        closeAfterSpawningProcess: false
      ),
      error: .fileDescriptor(errorDescriptor, closeAfterSpawningProcess: false)
    ) { execution in
      onStart?(execution.processIdentifier.value)
    }
    try Task.checkCancellation()
    return Result(
      terminationStatus: result.terminationStatus,
      arguments: arguments,
      standardOutput: try Data(contentsOf: output, options: .mappedIfSafe),
      standardError: try Data(contentsOf: errors, options: .mappedIfSafe)
    )
  }
}
