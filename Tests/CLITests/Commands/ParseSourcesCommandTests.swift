import ArgumentParser
import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Parsed-source command")
struct ParseSourcesCommandTests {
  @Test("Files and directories produce one portable archive")
  func sourceInputs() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App.swift": "final class App {}",
      "Generated/Model.swift": "struct Model {}",
      "Generated/Data.txt": "ignored",
    ])
    let output = project.fileURL(for: "Output/sources.pack")
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: project.fileURL(for: "Generated/Empty"),
      withIntermediateDirectories: true
    )
    let command = try ParseSourcesCommand.parse([
      "--input", project.fileURL(for: "Sources/App.swift").path,
      "--path", "Sources/App.swift",
      "--input", project.fileURL(for: "Generated").path,
      "--path", "Generated",
      "--swift-language-mode", "5",
      "--output", output.path,
    ])

    try await command.run()
    try FileManager.default.removeItem(
      at: project.fileURL(for: "Generated")
    )
    try FileManager.default.removeItem(
      at: project.fileURL(for: "Sources/App.swift")
    )

    let prepared = try ParsedSourceArchive.load(
      [output],
      rootedAt: project.rootURL.path
    )
    let codebase = CodebaseLoading(
      parseCachePolicy: .disabled,
      preparedSources: prepared
    ).apply(to: Codebase(root: .directory(project.rootURL.path)))
    let files = try await codebase.files

    #expect(files.map(\.path) == [
      project.fileURL(for: "Generated/Model.swift").path,
      project.fileURL(for: "Sources/App.swift").path,
    ])
    #expect(files.allSatisfy { $0.swiftLanguageMode == .v5 })
    let folders = try await codebase.checkFolderLayout(
      matching: "Generated",
      containing: ["Empty"]
    )
    #expect(folders.missingFolders.isEmpty)
    #expect(folders.unexpectedFolders.isEmpty)
  }

  @Test("Each input takes one portable path")
  func inputPathCount() async throws {
    let command = try ParseSourcesCommand.parse([
      "--input", "Sources/App.swift",
      "--output", "sources.pack",
    ])

    await #expect(throws: (any Error).self) {
      try await command.run()
    }
  }

  @Test("Language mode takes 4, 5 or 6")
  func languageMode() async throws {
    let command = try ParseSourcesCommand.parse([
      "--swift-language-mode", "7",
      "--output", "sources.pack",
    ])

    await #expect(throws: (any Error).self) {
      try await command.run()
    }
  }
}
