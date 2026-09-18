import Bylaws
import Foundation
import Testing

@Suite(
  "Performance",
  .enabled(if: ProcessInfo.processInfo.environment["BYLAWS_PERF"] != nil)
)
struct PerformanceTests {
  @Test(
    "A large codebase parses within the time limit",
    .timeLimit(.minutes(2))
  )
  func parsesLargeCodebase() async throws {
    let packageRoot = try Codebase.automaticRoot(above: #filePath)
    let swiftSyntaxSources = URL(fileURLWithPath: packageRoot)
      .appendingPathComponent(".build/checkouts/swift-syntax/Sources")
      .path
    let codebase = Codebase(root: .directory(swiftSyntaxSources))

    let start = Date()
    let classes = try await codebase.classes
    let uncachedParseDuration = Date().timeIntervalSince(start)

    let files = try await codebase.files
    let functions = try await codebase.functions
    let cachedReadDuration = Date().timeIntervalSince(start)
      - uncachedParseDuration

    let syntaxStart = Date()
    let syntaxNodes = try await codebase.syntaxNodes(of: .functionCall)
    let syntaxDuration = Date().timeIntervalSince(syntaxStart)

    print("""
    [perf] \(files.count) files, \(classes.count) classes, \
    \(functions
      .count) functions, uncached parse \(uncachedParseDuration), \
    cached reads \(cachedReadDuration), \(syntaxNodes.count) call nodes, \
    call-node model \(syntaxDuration)
    """)
    #expect(files.count > 100)
    #expect(!functions.isEmpty)
  }
}
