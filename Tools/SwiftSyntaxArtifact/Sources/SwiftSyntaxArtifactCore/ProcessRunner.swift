import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ProcessRunner: Sendable {
  func run(
    _ executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
  ) throws {
    let process = process(
      executable,
      arguments: arguments,
      currentDirectory: currentDirectory
    )
    try process.run()
    process.waitUntilExit()
    try check(process, executable: executable, arguments: arguments)
  }

  func output(
    _ executable: String,
    arguments: [String],
    currentDirectory: URL? = nil
  ) throws -> String {
    let output = Pipe()
    let process = process(
      executable,
      arguments: arguments,
      currentDirectory: currentDirectory
    )
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try check(process, executable: executable, arguments: arguments)
    guard let result = String(data: data, encoding: .utf8) else {
      throw ArtifactError("Command returned text that is not UTF-8.")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func process(
    _ executable: String,
    arguments: [String],
    currentDirectory: URL?
  ) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    return process
  }

  private func check(
    _ process: Process,
    executable: String,
    arguments: [String]
  ) throws {
    guard process.terminationReason == .exit,
          process.terminationStatus == EXIT_SUCCESS
    else {
      throw ArtifactError(
        "Command failed: \(([executable] + arguments).joined(separator: " "))"
      )
    }
  }
}
