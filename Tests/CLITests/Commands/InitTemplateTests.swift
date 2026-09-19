import BylawsCore
import BylawsInterpreter
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Init template")
struct InitTemplateTests {
  @Test("The template loads and every rule it declares is advisory")
  func templateLoads() async throws {
    let root = try Self.project()
    defer { try? FileManager.default.removeItem(atPath: root) }

    let program = await RuleProgram.discovered(atRoot: root)

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == [
      "public-api-docs", "no-print", "final-classes",
    ])
    #expect(program.rules.allSatisfy { $0.enforcement == .advisory })
    #expect(program.rules.allSatisfy { $0.hint != nil })
  }

  @Test("Each template rule explains the convention with examples")
  func templateExplainsRules() {
    #expect(RulesFileTemplate.content.components(separatedBy: "Bad:")
      .count == 4)
    #expect(RulesFileTemplate.content.components(separatedBy: "Good:")
      .count == 4)
  }

  @Test("Each template rule finds what it describes")
  func templateRulesRun() async throws {
    let root = try Self.project()
    defer { try? FileManager.default.removeItem(atPath: root) }

    let program = await RuleProgram.discovered(atRoot: root)
    var offendersByRule: [Rule.ID: [String]] = [:]
    for rule in program.rules {
      offendersByRule[rule.id] = try await rule.violations().offenders
        .compactMap(\.name)
    }

    #expect(offendersByRule["public-api-docs"] == ["Cart"])
    #expect(offendersByRule["no-print"] == ["print"])
    #expect(offendersByRule["final-classes"] == ["HomeScreen"])
  }

  @Test(
    "DocC examples are excluded unless the exclusion is removed",
    arguments: [
      "Sources/Guide.docc/Example.swift",
      "Sources/App/Guide.docc/Steps/Example.swift",
    ],
    [false, true]
  )
  func doccExamples(path: String, includesExamples: Bool) async throws {
    let root = try Self.project()
    defer { try? FileManager.default.removeItem(atPath: root) }

    let example = URL(fileURLWithPath: root).appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: example.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try "class DocumentationExample {}".write(
      to: example, atomically: true, encoding: .utf8
    )
    if includesExamples {
      try RulesFileTemplate.content.replacing(
        "\"**/*.docc/**\"", with: ""
      ).write(toFile: "\(root)/Bylaws.swift", atomically: true, encoding: .utf8)
    }

    let program = await RuleProgram.discovered(atRoot: root)
    #expect(program.diagnostics.isEmpty)
    let rule = try #require(program.rules.first { $0.id == "final-classes" })
    let offenders = try await rule.violations().offenders.compactMap(\.name)

    let expected = if includesExamples {
      ["DocumentationExample", "HomeScreen"]
    } else {
      ["HomeScreen"]
    }
    #expect(offenders.sorted() == expected)
  }

  private static func project() throws -> String {
    let manager = FileManager.default
    let root = NSTemporaryDirectory() + "bylaws-init-\(UUID().uuidString)"
    try manager.createDirectory(
      atPath: "\(root)/Sources/App",
      withIntermediateDirectories: true
    )
    try "// swift-tools-version: 6.0".write(
      toFile: "\(root)/Package.swift",
      atomically: true,
      encoding: .utf8
    )
    try """
    public struct Cart {}
    class HomeScreen {
      func log() { print("hi") }
    }
    """.write(
      toFile: "\(root)/Sources/App/Home.swift",
      atomically: true,
      encoding: .utf8
    )
    try RulesFileTemplate.content.write(
      toFile: "\(root)/Bylaws.swift",
      atomically: true,
      encoding: .utf8
    )
    return root
  }
}
