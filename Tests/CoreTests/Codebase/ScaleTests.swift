import Bylaws
import Foundation
import Testing

private let scaleClassCount = Int(
  ProcessInfo.processInfo.environment["BYLAWS_SCALE"] ?? ""
) ?? 0

private let generatedScaleRoot: Result<String, any Error> = Result {
  let manager = FileManager.default
  let publishedRoot = NSTemporaryDirectory()
    + "bylaws-scale-\(scaleClassCount)"
  if manager.fileExists(atPath: publishedRoot + "/Sources") {
    return publishedRoot
  }
  let stagingRoot = NSTemporaryDirectory()
    + "bylaws-scale-\(UUID().uuidString)"
  let sources = stagingRoot + "/Sources"
  try manager.createDirectory(
    atPath: sources, withIntermediateDirectories: true
  )
  let classesPerFile = 100
  let fileCount = max(scaleClassCount / classesPerFile, 0)
  for file in 1...max(fileCount, 1) where fileCount > 0 {
    let source = (1...classesPerFile).map {
      "final class Type\(file)_\($0) { var value = \($0) }"
    }.joined(separator: "\n")
    try source.write(
      toFile: "\(sources)/File\(file).swift",
      atomically: true, encoding: .utf8
    )
  }
  do {
    try manager.moveItem(atPath: stagingRoot, toPath: publishedRoot)
  } catch {
    guard manager.fileExists(atPath: publishedRoot + "/Sources") else {
      throw error
    }
    try? manager.removeItem(atPath: stagingRoot)
  }
  return publishedRoot
}

extension Codebase {
  fileprivate static let generatedScale = generatedScaleRoot.map {
    Codebase(root: .directory($0))
  }
}

@Suite("Scale", .enabled(if: scaleClassCount > 0))
struct ScaleTests {
  @Test(
    "Parameterised form checks every generated class",
    arguments: try await Codebase.generatedScale.get().classes
  )
  func classIsFinal(_ aClass: Class) {
    #expect(aClass.isFinal)
  }

  @Test("Collection form checks every generated class")
  func collectionForm() async throws {
    let start = Date()
    let violations = try await Codebase.generatedScale.get().classes
      .violations(of: .isFinal)
    let elapsed = Date().timeIntervalSince(start)
    print(
      "[scale] collection form checked \(violations.checkedCount) classes in \(elapsed)s"
    )
    #expect(violations.isEmpty)
    #expect(violations.checkedCount == scaleClassCount)
  }
}
