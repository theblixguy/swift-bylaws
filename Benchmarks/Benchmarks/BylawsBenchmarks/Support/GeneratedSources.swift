import Foundation

final class GeneratedSources: Sendable {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "bylaws-benchmark-sources-\(UUID().uuidString)",
      isDirectory: true
    )
    do {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Sources"),
        withIntermediateDirectories: true
      )
      for file in 1...100 {
        let source = (1...10).map {
          "final class Type\(file)_\($0): BaseViewModel { var value = \($0) }"
        }.joined(separator: "\n")
        try source.write(
          to: root.appendingPathComponent("Sources/File\(file).swift"),
          atomically: true,
          encoding: .utf8
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
