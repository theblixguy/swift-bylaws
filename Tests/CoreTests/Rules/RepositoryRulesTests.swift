import Bylaws
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Repository rule regressions")
struct RepositoryRulesTests {
  @Test("Module boundaries permit only declared dependencies", arguments: [
    ("BylawsIndexStore", "BylawsCore", 1),
    ("BylawsPaths", "BylawsSemantics", 1),
    ("BylawsCore", "BylawsInterpreter", 1),
    ("BylawsRunner", "BylawsLSP", 1),
    ("BylawsIndexStore", "BylawsPaths", 0),
    ("BylawsCore", "BylawsSemantics", 0),
    ("BylawsLSP", "BylawsRunner", 0),
    ("BylawsPaths", "Foundation", 0),
  ])
  func moduleImports(
    module: String,
    dependency: String,
    expected: Int
  ) async throws {
    try await check(
      "module-boundaries", path: "Sources/\(module)/Mock.swift",
      source: "import \(dependency)", expected: expected
    )
  }

  @Test("Unchecked Sendable produces violations", arguments: [
    "final class Mock: @unchecked Sendable {}",
    "struct Mock: @unchecked Sendable {}",
    "enum Mock: @unchecked Sendable {}",
    "actor Mock: @unchecked Sendable {}",
    "struct Mock {}\nextension Mock: @unchecked Sendable {}",
  ])
  func uncheckedSendable(source: String) async throws {
    try await check(
      "safe-concurrency", path: "Sources/BylawsCore/Mock.swift",
      source: source, expected: 1
    )
  }

  @Test("Shared rules reject violations and retain permitted code", arguments: [
    (
      "safe-concurrency",
      "Sources/BylawsCore/Mock.swift",
      "struct Mock: Sendable {}",
      0
    ),
    (
      "safe-concurrency",
      "Sources/BylawsCore/Mock.swift",
      "nonisolated(unsafe) var count = 0",
      1
    ),
    ("testing-imports", "Sources/BylawsPaths/Mock.swift", "import Testing", 1),
    ("testing-imports", "Sources/Bylaws/Mock.swift", "import Testing", 0),
    ("testing-imports", "Sources/BylawsIndex/Mock.swift", "import Testing", 0),
    (
      "testing-imports",
      "Benchmarks/Benchmarks/BylawsBenchmarks/Mock.swift",
      "import Testing",
      1
    ),
    (
      "testing-imports",
      "Benchmarks/Benchmarks/BylawsBenchmarks/Mock.swift",
      "import Benchmark",
      0
    ),
    (
      "public-protocol-docs",
      "Sources/Bylaws/Mock.swift",
      "public protocol Mock {}",
      1
    ),
    (
      "public-protocol-docs",
      "Sources/Bylaws/Mock.swift",
      "/// A test protocol.\npublic protocol Mock {}",
      0
    ),
    (
      "public-protocol-docs",
      "Sources/Bylaws/Mock.swift",
      "protocol Mock {}",
      0
    ),
    (
      "syntax-imports",
      "Sources/BylawsCore/Mock.swift",
      "import SwiftSyntax",
      1
    ),
    ("syntax-imports", "Sources/Bylaws/Mock.swift", "import SwiftParser", 1),
    (
      "syntax-imports",
      "Sources/BylawsCore/Mock.swift",
      "import BylawsSyntax",
      1
    ),
    (
      "syntax-imports",
      "Sources/BylawsSemantics/Mock.swift",
      "import SwiftSyntax",
      0
    ),
    (
      "syntax-imports",
      "Sources/BylawsInterpreter/Mock.swift",
      "import SwiftParser",
      0
    ),
    (
      "syntax-imports",
      "Sources/BylawsSyntax/Mock.swift",
      "import SwiftSyntax",
      0
    ),
    ("final-classes", "Sources/BylawsCore/Mock.swift", "class Mock {}", 1),
    (
      "final-classes",
      "Benchmarks/Benchmarks/BylawsBenchmarks/Mock.swift",
      "class Mock {}",
      1
    ),
    (
      "final-classes",
      "Sources/BylawsCore/Mock.swift",
      "final class Mock {}",
      0
    ),
    (
      "final-classes",
      "Sources/BylawsCore/Mock.swift",
      "class LexicalRegionVisitor {}",
      1
    ),
    (
      "final-classes",
      "Sources/BylawsSemantics/Collector/Source/LexicalRegionVisitor.swift",
      "class LexicalRegionVisitor {}",
      0
    ),
    (
      "clock-sleep",
      "Sources/BylawsCore/Mock.swift",
      "func run() async throws { try await Task.sleep(for: .seconds(1)) }",
      1
    ),
    (
      "clock-sleep",
      "Benchmarks/Benchmarks/BylawsBenchmarks/Mock.swift",
      "func run() async throws { try await Task.sleep(for: .seconds(1)) }",
      1
    ),
    (
      "clock-sleep",
      "Tests/CoreTests/Mock.swift",
      "func run() async throws { try await Task.sleep(nanoseconds: 1) }",
      1
    ),
    (
      "clock-sleep",
      "Tests/SampleApp/Mock.swift",
      "func run() async throws { try await Task.sleep(nanoseconds: 1) }",
      0
    ),
    (
      "clock-sleep",
      "Tests/CoreTests/Mock.swift",
      "let source = \"Task.sleep(nanoseconds: 1)\"",
      0
    ),
  ])
  func sharedRules(
    id: String,
    path: String,
    source: String,
    expected: Int
  ) async throws {
    try await check(id, path: path, source: source, expected: expected)
  }

  private func check(
    _ id: String, path: String, source: String, expected: Int
  ) async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let rules = try String(
      contentsOf: root.appendingPathComponent("Bylaws.swift"), encoding: .utf8
    )
    let project = try TemporaryProject(files: [
      "Bylaws.swift": rules,
      "Package.swift": "",
      path: source,
    ])
    let program = await RuleProgram.loaded(fromFiles: [
      project.fileURL(for: "Bylaws.swift").path,
    ])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    let rule = try #require(program.rules.first { $0.id.rawValue == id })
    let findings = try await rule.findings()
    #expect(findings.violations.count == expected, "\(findings.violations)")
  }
}
