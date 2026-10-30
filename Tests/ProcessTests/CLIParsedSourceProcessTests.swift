import BylawsCore
import BylawsSemantics
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Bylaws parsed-source input")
struct CLIParsedSourceProcessTests {
  @Test("Lint reads declarations from an archive")
  func archivedSource() throws {
    let source = "class Archived {}"
    let project = try CLIProcessProject(
      source: source,
      rules: CLIProcessMock.finalClassesRule
    )
    let sourceURL = project.root.appendingPathComponent(
      "Sources/App/App.swift"
    )
    let archiveURL = project.root.appendingPathComponent("sources.pack")
    let file = try FileCollector.collect(source: source, path: sourceURL.path)
    try ParsedSourceArchive.write([
      .init(relativePath: "Sources/App/App.swift", sourceFile: file),
    ], to: archiveURL)
    try FileManager.default.removeItem(at: sourceURL)

    let result = try project.run("--parsed-sources", archiveURL.path)

    #expect(result.status == 1)
    #expect(result.standardOutput
      .contains("Archived violates 'Classes are final'"))
  }

  @Test("Unreadable archives fail lint")
  func unreadableArchive() throws {
    let project = try CLIProcessProject(
      source: "final class App {}",
      rules: CLIProcessMock.finalClassesRule
    )
    let archiveURL = project.root.appendingPathComponent("sources.pack")
    try Data("not an archive".utf8).write(to: archiveURL)

    let result = try project.run("--parsed-sources", archiveURL.path)

    #expect(result.status == 2)
    #expect(result.standardOutput.contains(
      "Cannot read the parsed-source archive at '\(archiveURL.path)'."
    ))
  }
}
