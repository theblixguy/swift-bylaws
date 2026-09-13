import Foundation

struct CLIParseBenchmark: Sendable {
  let executable: URL
  let root: URL

  init(executable: URL, root: URL, including: String) throws {
    self.executable = executable
    self.root = root
    try """
    let app = Codebase(including: [\(String(reflecting: including))])
    Rule("files", "Files have Swift extension") {
      app.files.violations(of: .suffixed(".swift"))
    }
    """.write(
      to: root.appendingPathComponent("Bylaws.swift"),
      atomically: true,
      encoding: .utf8
    )
  }

  func run() throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["lint", "--root", root.path]
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["BYLAWS_DISABLE_PARSE_CACHE": "true"],
      uniquingKeysWith: { _, value in value }
    )
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw Failure(status: process.terminationStatus)
    }
  }

  private struct Failure: Error {
    let status: Int32
  }
}
