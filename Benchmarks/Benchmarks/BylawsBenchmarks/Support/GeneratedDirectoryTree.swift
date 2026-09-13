import Foundation

final class GeneratedDirectoryTree: Sendable {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "bylaws-benchmark-tree-\(UUID().uuidString)",
      isDirectory: true
    )
    do {
      let sources = root.appendingPathComponent("Sources")
      let included = sources.appendingPathComponent("Included")
      try FileManager.default.createDirectory(
        at: included,
        withIntermediateDirectories: true
      )
      for index in 1...1000 {
        try FileManager.default.createDirectory(
          at: sources.appendingPathComponent("Unrelated\(index)"),
          withIntermediateDirectories: false
        )
      }
    } catch {
      try? FileManager.default.removeItem(at: root)
      throw error
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }
}
