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

  @Test("The template contains active rules alone")
  func templateHasNoCommentedCode() {
    let commentLines = RulesFileTemplate.content.split(separator: "\n")
      .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    #expect(commentLines.isEmpty)
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
