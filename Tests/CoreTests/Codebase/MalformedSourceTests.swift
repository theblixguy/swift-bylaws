import Bylaws
import Foundation
import Testing

@Suite("Malformed sources")
struct MalformedSourceTests {
  @Test("A file that does not parse fails the query")
  func malformedFileFailsTheQuery() async throws {
    let manager = FileManager.default
    let root = NSTemporaryDirectory() + "bylaws-malformed-\(UUID().uuidString)"
    defer { try? manager.removeItem(atPath: root) }
    try manager.createDirectory(
      atPath: "\(root)/Sources",
      withIntermediateDirectories: true
    )
    let path = "\(root)/Sources/Broken.swift"
    try "struct Broken {".write(
      toFile: path,
      atomically: true,
      encoding: .utf8
    )

    await #expect {
      try await Codebase(root: .directory(root)).structs
    } throws: { error in
      guard case let CodebaseError.didNotParse(diagnostics) = error
      else { return false }
      return diagnostics.map(\.location.filePath) == [path]
    }
  }

  @Test("In-memory source that does not parse fails the query")
  func malformedInMemorySourceFailsTheQuery() async throws {
    let codebase = Codebase(root: .sources(["Broken.swift": "struct Broken {"]))
    await #expect(throws: (any Error).self) {
      try await codebase.structs
    }
  }

  @Test("A declaration hidden in a malformed file fails the query")
  func hiddenDeclarationFailsTheQuery() async throws {
    let source = "let banner = \"\"\"\nclass Hidden {}\n"
    let codebase = Codebase(root: .sources(["Hidden.swift": source]))
    await #expect(throws: (any Error).self) {
      try await codebase.classes
    }
  }
}
