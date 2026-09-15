import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Symbolic source files")
struct SymbolicFileTests {
  @Test("Read linked files at their logical paths")
  func logicalPaths() async throws {
    let project = try TemporaryProject(files: [
      "Stored/Model.swift": "class Model {}",
      "Sources/Other.swift": "final class Other {}",
    ])
    try FileManager.default.createSymbolicLink(
      at: project.fileURL(for: "Sources/Model.swift"),
      withDestinationURL: project.fileURL(for: "Stored/Model.swift")
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    let classes = try await codebase.classes
    let model = try #require(classes.first { $0.name == "Model" })

    #expect(classes.map(\.name).sorted() == ["Model", "Other"])
    #expect(model.location.filePath.hasSuffix("/Sources/Model.swift"))
    #expect(!model.isFinal)
  }

  @Test("Exclude linked files by their logical paths")
  func excludedPath() async throws {
    let project = try TemporaryProject(files: [
      "Stored/Model.swift": "class Model {}",
      "Sources/Other.swift": "final class Other {}",
    ])
    try FileManager.default.createSymbolicLink(
      at: project.fileURL(for: "Sources/Model.swift"),
      withDestinationURL: project.fileURL(for: "Stored/Model.swift")
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"],
      excluding: ["Sources/Model.swift"]
    )

    let classes = try await codebase.classes

    #expect(classes.map(\.name) == ["Other"])
  }

  @Test("Skip broken links and link loops", arguments: [
    "Missing.swift", "Linked.swift",
  ])
  func unresolvedLink(_ destination: String) async throws {
    let project =
      try TemporaryProject(files: ["Sources/Model.swift": "class Model {}"])
    try FileManager.default.createSymbolicLink(
      atPath: project.fileURL(for: "Sources/Linked.swift").path,
      withDestinationPath: destination
    )

    let classes = try await Codebase(root: .directory(project.rootURL.path))
      .classes

    #expect(classes.map(\.name) == ["Model"])
  }
}
