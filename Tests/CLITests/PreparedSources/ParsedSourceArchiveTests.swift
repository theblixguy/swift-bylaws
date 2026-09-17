import BylawsCore
import BylawsSemantics
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Parsed-source archives")
struct ParsedSourceArchiveTests {
  @Test("Round trip rebases paths and preserves language modes")
  func roundTrip() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let archiveURL = directory.appendingPathComponent("sources.pack")
    let source = "final class Model {}"
    let file = try FileCollector.collect(
      source: source,
      path: "/first/checkout/Sources/Model.swift",
      swiftLanguageMode: .v5
    )
    try ParsedSourceArchive.write([
      .init(relativePath: "Sources/Model.swift", sourceFile: file),
    ], to: archiveURL)

    let prepared = try ParsedSourceArchive.load(
      [archiveURL],
      rootedAt: "/second/checkout"
    )
    let loaded = try #require(prepared.files.first)

    #expect(loaded.path == "/second/checkout/Sources/Model.swift")
    #expect(loaded.sourceText == source)
    #expect(loaded.swiftLanguageMode == .v5)
    #expect(loaded.classes.map(\.name) == ["Model"])
    #expect(loaded.classes.first?.location.filePath == loaded.path)
    #expect(prepared.directories == ["/second/checkout/Sources"])
  }

  @Test("Unsafe paths fail", arguments: [
    "/Sources/Model.swift",
    "../Sources/Model.swift",
    "Sources/./Model.swift",
    "Sources//Model.swift",
  ])
  func unsafePath(path: String) throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = try FileCollector.collect(
      source: "class Model {}",
      path: path
    )

    #expect(throws: ParsedSourceArchive.Error.pathMustBeRelative(path)) {
      try ParsedSourceArchive.write([
        .init(relativePath: path, sourceFile: file),
      ], to: directory.appendingPathComponent("sources.pack"))
    }
  }

  @Test("Corrupt archives fail")
  func corruptArchive() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let archiveURL = directory.appendingPathComponent("sources.pack")
    try Data("not an archive".utf8).write(to: archiveURL)

    #expect(
      throws: ParsedSourceArchive.Error.cannotRead(archiveURL.path)
    ) {
      try ParsedSourceArchive(contentsOf: archiveURL)
    }
  }

  @Test("Corrupt directory entries fail")
  func corruptDirectory() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let archiveURL = directory.appendingPathComponent("sources.pack")
    try ParsedSourceArchive.write(
      [], directories: ["Sources"], to: archiveURL
    )
    var data = try Data(contentsOf: archiveURL)
    data[0] = 1
    try data.write(to: archiveURL)

    #expect(throws: ParsedSourceArchive.Error.cannotRead(archiveURL.path)) {
      try ParsedSourceArchive.load([archiveURL], rootedAt: "/checkout")
    }
  }

  @Test("Duplicate paths across archives fail")
  func duplicatePaths() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstURL = directory.appendingPathComponent("first.pack")
    let secondURL = directory.appendingPathComponent("second.pack")
    let path = "Sources/Model.swift"
    let file = try FileCollector.collect(source: "class Model {}", path: path)
    let entry = ParsedSourceArchive.Entry(
      relativePath: path,
      sourceFile: file
    )
    try ParsedSourceArchive.write([entry], to: firstURL)
    try ParsedSourceArchive.write([entry], to: secondURL)

    #expect(throws: ParsedSourceArchive.Error.duplicatePath(
      "/checkout/Sources/Model.swift"
    )) {
      try ParsedSourceArchive.load(
        [firstURL, secondURL],
        rootedAt: "/checkout"
      )
    }
  }

  @Test("Archived directories include parent folders")
  func directoryParents() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let archiveURL = root.appendingPathComponent("sources.pack")
    try ParsedSourceArchive.write(
      [], directories: ["Features/Orders/Models"], to: archiveURL
    )

    let prepared = try ParsedSourceArchive.load(
      [archiveURL],
      rootedAt: "/checkout"
    )

    #expect(prepared.directories == [
      "/checkout/Features",
      "/checkout/Features/Orders",
      "/checkout/Features/Orders/Models",
    ])
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
