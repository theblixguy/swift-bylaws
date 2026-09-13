#!/usr/bin/env swift

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private struct CommandFailure: Error, CustomStringConvertible {
  let description: String
}

private struct ProcessResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

private func run(
  _ executable: URL,
  arguments: [String],
  in directory: URL? = nil
) throws -> ProcessResult {
  let captureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("bylaws-command-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: captureDirectory) }
  try FileManager.default.createDirectory(
    at: captureDirectory,
    withIntermediateDirectories: true
  )
  let outputURL = captureDirectory.appendingPathComponent("stdout")
  let errorURL = captureDirectory.appendingPathComponent("stderr")
  try Data().write(to: outputURL)
  try Data().write(to: errorURL)
  let output = try FileHandle(forWritingTo: outputURL)
  let error = try FileHandle(forWritingTo: errorURL)

  let process = Process()
  process.executableURL = executable
  process.arguments = arguments
  process.currentDirectoryURL = directory
  process.standardOutput = output
  process.standardError = error
  try process.run()
  process.waitUntilExit()
  try output.close()
  try error.close()
  return ProcessResult(
    status: process.terminationStatus,
    standardOutput: String(
      decoding: try Data(contentsOf: outputURL),
      as: UTF8.self
    ),
    standardError: String(
      decoding: try Data(contentsOf: errorURL),
      as: UTF8.self
    )
  )
}

private func executable(at path: String) throws -> URL {
  let url = URL(fileURLWithPath: path).standardizedFileURL
  guard FileManager.default.isExecutableFile(atPath: url.path) else {
    throw CommandFailure(description: "Executable does not exist: \(url.path)")
  }
  return url
}

private func requireSuccess(
  _ result: ProcessResult,
  command: String
) throws {
  guard result.status == 0 else {
    throw CommandFailure(
      description: """
      \(command) exited with status \(result.status).
      \(result.standardOutput)\(result.standardError)
      """
    )
  }
}

private func testVersion(
  of executable: URL,
  command: String,
  expectedVersion: String
) throws {
  let result = try run(executable, arguments: ["--version"])
  try requireSuccess(result, command: "\(command) --version")
  let version = result.standardOutput.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard version == expectedVersion else {
    throw CommandFailure(
      description: "Expected \(command) version \(expectedVersion), got \(version)."
    )
  }
  guard result.standardError.isEmpty else {
    throw CommandFailure(
      description: "\(command) --version wrote to standard error: \(result.standardError)"
    )
  }
}

private func testRule(with executable: URL) throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("bylaws-release-test-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: root) }
  let sources = root.appendingPathComponent("Sources/App")
  try FileManager.default.createDirectory(
    at: sources,
    withIntermediateDirectories: true
  )
  try Data().write(to: root.appendingPathComponent("Package.swift"))
  try "final class App {}".write(
    to: sources.appendingPathComponent("App.swift"),
    atomically: true,
    encoding: .utf8
  )
  try """
  let app = Codebase(including: ["Sources/**"])

  Rule("final-classes", "Classes are final") {
    app.classes.violations(of: .isFinal)
  }
  """.write(
    to: root.appendingPathComponent("Bylaws.swift"),
    atomically: true,
    encoding: .utf8
  )

  let result = try run(
    executable,
    arguments: ["lint", "--root", root.path],
    in: root
  )
  try requireSuccess(result, command: "bylaws lint")
  let output = result.standardOutput.trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard output == "Checked 1 rule: 0 violations." else {
    throw CommandFailure(description: "Unexpected lint output: \(output)")
  }
  guard result.standardError.isEmpty else {
    throw CommandFailure(
      description: "bylaws lint wrote to standard error: \(result.standardError)"
    )
  }
}

private func test(arguments: [String]) throws {
  guard arguments.count == 2 || arguments.count == 3 else {
    throw CommandFailure(
      description: "Usage: \(CommandLine.arguments[0]) BYLAWS VERSION [BYLAWS_LSP]"
    )
  }
  let bylaws = try executable(at: arguments[0])
  let expectedVersion = arguments[1]
  try testVersion(
    of: bylaws,
    command: "bylaws",
    expectedVersion: expectedVersion
  )
  try testRule(with: bylaws)

  if arguments.count == 3 {
    try testVersion(
      of: executable(at: arguments[2]),
      command: "bylaws-lsp",
      expectedVersion: expectedVersion
    )
  }
}

private func stop(with message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(EXIT_FAILURE)
}

do {
  try test(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CommandFailure {
  stop(with: error.description)
} catch {
  stop(with: error.localizedDescription)
}
