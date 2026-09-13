import BylawsCore
import BylawsPaths
import Foundation
import Testing
@testable import bylaws_cli
@testable import BylawsRunner

@Suite("Project root resolution")
struct ProjectRootTests {
  @Test("A Bazel run resolves the workspace it names")
  func bazelWorkspace() throws {
    let root = try ProjectRoot.resolve(
      explicit: nil,
      environment: ["BUILD_WORKSPACE_DIRECTORY": "/project/../workspace"]
    )

    #expect(root.string == "/workspace")
  }

  @Test("An explicit root takes priority over the Bazel workspace")
  func explicitRootWins() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bylaws-root-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let root = try ProjectRoot.resolve(
      explicit: directory.path,
      environment: ["BUILD_WORKSPACE_DIRECTORY": NSTemporaryDirectory()]
    )

    #expect(root.string == directory.path)
  }

  @Test("A relative explicit root resolves from the working directory")
  func relativeExplicitRoot() throws {
    let relativePath = ".build/bylaws-root-\(UUID().uuidString)"
    let absolutePath = FileManager.default.currentDirectoryPath
      + "/\(relativePath)"
    try FileManager.default.createDirectory(
      atPath: absolutePath,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(atPath: absolutePath) }

    let root = try ProjectRoot.resolve(
      explicit: relativePath,
      environment: [:]
    )

    #expect(root.string == absolutePath)
  }

  @Test("An empty workspace variable uses the directory search")
  func emptyWorkspace() throws {
    let root = try ProjectRoot.resolve(
      explicit: nil,
      environment: ["BUILD_WORKSPACE_DIRECTORY": ""]
    )

    #expect(!root.string.isEmpty)
  }

  @Test("An explicit root must be a directory")
  func explicitRootMustBeDirectory() {
    let path = "/missing/bylaws-project-root"

    #expect(throws: CodebaseError.notADirectory(path: path)) {
      try ProjectRoot.resolve(explicit: path, environment: [:])
    }
  }
}
