import BylawsTestSupport
import Foundation

enum CLIProcessMock {
  static let finalClassesRule = """
  let app = Codebase(including: ["Sources/**"])

  Rule("final-classes", "Classes are final") {
    app.classes.violations(of: .isFinal)
  }
  """
}

final class CLIProcessProject {
  private let project: TemporaryProject
  var root: URL { project.rootURL }

  init(
    source: String,
    rules: String?,
    extraFiles: [String: String] = [:],
    writesProjectMarker: Bool = true
  ) throws {
    var files = ["Sources/App/App.swift": source]
    if let rules {
      files["Bylaws.swift"] = rules
    }
    if writesProjectMarker {
      files["Package.swift"] = ""
    }
    files.merge(extraFiles) { _, replacement in replacement }
    project = try TemporaryProject(
      files: files,
      directoryNamePrefix: "bylaws-process"
    )
  }

  func run(_ arguments: String...) throws -> Result {
    try run("lint", arguments: arguments, usesExplicitRoot: true)
  }

  func runRules(_ arguments: String...) throws -> Result {
    try run("rules", arguments: arguments, usesExplicitRoot: true)
  }

  func runResolvingRoot() throws -> Result {
    try run("lint", arguments: [], usesExplicitRoot: false)
  }

  private func run(
    _ command: String,
    arguments: [String],
    usesExplicitRoot: Bool
  ) throws -> Result {
    let outputURL = root.appendingPathComponent("stdout-\(UUID().uuidString)")
    let errorURL = root.appendingPathComponent("stderr-\(UUID().uuidString)")
    try Data().write(to: outputURL)
    try Data().write(to: errorURL)
    let standardOutput = try FileHandle(forWritingTo: outputURL)
    let standardError = try FileHandle(forWritingTo: errorURL)
    defer {
      try? standardOutput.close()
      try? standardError.close()
      try? FileManager.default.removeItem(at: outputURL)
      try? FileManager.default.removeItem(at: errorURL)
    }
    let process = Process()
    process.executableURL = try Self.executable()
    process.arguments = [command]
      + (usesExplicitRoot ? ["--root", root.path] : [])
      + arguments
    process.currentDirectoryURL = root
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()
    try standardOutput.close()
    try standardError.close()

    return Result(
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

  func writeSource(_ source: String) throws {
    try project.write(source, to: "Sources/App/App.swift")
  }

  private static func executable() throws -> URL {
    try ExecutableLocator.locate(
      named: "bylaws",
      overriddenBy: "BYLAWS_CLI_BINARY",
      relativeTo: #filePath
    )
  }

  struct Result {
    let status: Int32
    let standardOutput: String
    let standardError: String
  }
}
