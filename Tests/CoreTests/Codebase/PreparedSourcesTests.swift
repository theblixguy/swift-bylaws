import BylawsSemantics
import Foundation
import Testing
@testable import BylawsCore

@Suite("Prepared sources")
struct PreparedSourcesTests {
  @Test("Duplicate file paths fail")
  func duplicatePaths() throws {
    let path = "/checkout/Sources/Model.swift"
    let file = try FileCollector.collect(source: "class Model {}", path: path)

    #expect(throws: PreparedSources.Error.duplicatePath(path)) {
      try PreparedSources(files: [file, file])
    }
  }

  @Test("Codebase filters prepared sources")
  func codebaseFiltering() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let sources = [
      ("Sources/App/Included.swift", "class Included {}"),
      ("Sources/App/Excluded.swift", "class Excluded {}"),
      ("Sources/Other/Other.swift", "class Other {}"),
    ]
    let files = try sources.map { path, source in
      try FileCollector.collect(
        source: source,
        path: root.appendingPathComponent(path).path
      )
    }
    let prepared = try PreparedSources(files: files)
    let codebase = CodebaseLoading(
      parseCachePolicy: .disabled,
      preparedSources: prepared
    ).apply(to: Codebase(
      root: .directory(root.path),
      including: ["Sources/App/**"],
      excluding: ["**/Excluded.swift"]
    ))

    #expect(try await codebase.classes.map(\.name) == ["Included"])
  }

  @Test("Folder checks read prepared directories")
  func preparedDirectories() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let prepared = try PreparedSources(
      files: [],
      directories: [root.appendingPathComponent("Generated/Empty").path]
    )
    let codebase = CodebaseLoading(
      parseCachePolicy: .disabled,
      preparedSources: prepared
    ).apply(to: Codebase(root: .directory(root.path)))

    let result = try await codebase.checkFolderLayout(
      matching: "Generated",
      containing: ["Empty"]
    )

    #expect(result.missingFolders.isEmpty)
    #expect(result.unexpectedFolders.isEmpty)
  }
}
