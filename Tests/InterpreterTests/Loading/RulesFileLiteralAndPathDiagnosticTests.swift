import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rules-file literals and paths")
struct RulesFileLiteralAndPathDiagnosticTests {
  @Test("A relative discovery root becomes absolute")
  func relativeDiscoveryRootBecomesAbsolute() async throws {
    let workingDirectory = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath
    )
    let parent = workingDirectory
      .appendingPathComponent(".build/interpreter-tests")
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App/A.swift": "class A {}",
    ], under: parent)
    let relativeRoot = String(project.rootURL.path.dropFirst(
      workingDirectory.path.count + 1
    ))

    let program = await RuleProgram.discovered(atRoot: relativeRoot)
    #expect(program.diagnostics.isEmpty)
    let rule = try #require(program.rules.first)
    #expect(rule.location.filePath.hasPrefix(project.rootURL.path))
    let violations = try await rule.violations()
    #expect(violations.offenders.map(\.name) == ["A"])
    #expect(violations.offenders.allSatisfy {
      $0.location.filePath.hasPrefix(project.rootURL.path)
    })
  }

  @Test("String literals use their represented values")
  func stringLiteralsUseRepresentedValues() async throws {
    let source = ##"""
    let app = Codebase(including: ["Sources/\u{41}pp/**"])
    Rule(
      "line\nid",
      #"Raw\#nname"#,
      hint: """
    first
      second
    """
    ) {
      app.classes.suffixed("\u{4D}odel").violations(of: .isFinal)
    }
    """##
    let (program, project) = try await diagnostics(
      forRules: source,
      sources: ["Sources/App/AModel.swift": "class AModel {}"]
    )

    #expect(program.diagnostics.isEmpty)
    let rule = try #require(program.rules.first)
    #expect(rule.id.rawValue == "line\nid")
    #expect(rule.name == "Raw\nname")
    #expect(rule.hint == "first\n  second")
    let violations = try await rule.violations()
    #expect(violations.offenders.map(\.name) == ["AModel"])
    #expect(project.rootURL.path.hasPrefix("/"))
  }

  @Test("Parser rejects an interpolated string where a literal is required")
  func interpolatedString() async throws {
    let (program, _) = try await diagnostics(forRules: """
    let app = Codebase(including: ["Sources/**"])
    let suffix = "ViewModel"
    Rule("r", "Rule \\(suffix)") { app.classes.violations(of: .isFinal) }
    """)

    #expect(!program.errors.isEmpty)
  }

  @Test("A missing rules file produces one diagnostic")
  func missingRulesFile() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/A.swift": "class A {}",
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    let diagnostic = try #require(program.errors.first)
    #expect(diagnostic.message.contains("no Bylaws.swift found"))
  }

  @Test("A relative explicit rules path resolves from the working directory")
  func relativeRulesPath() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("r", "Rule") { app.classes.violations(of: .isFinal) }
      """,
      "Sources/App.swift": "final class App {}",
    ])
    let absolutePath = "\(project.rootURL.path)/Bylaws.swift"
    let relativePath = relative(
      absolutePath,
      to: FileManager.default.currentDirectoryPath
    )

    let program = await RuleProgram.loaded(fromFiles: [relativePath])

    #expect(program.errors.isEmpty)
    #expect(program.rules.first?.location.filePath == absolutePath)
  }

  @Test("An unreadable rules file reports a file-read error")
  func unreadableRulesFile() async {
    let path = "/nonexistent/bylaws-rules.swift"
    let program = await RuleProgram.loaded(fromFiles: [path])

    #expect(
      program.errors.map(\.message) == [
        "cannot read the file: \(readFailureDescription(at: path))",
      ]
    )
  }

  private func relative(_ path: String, to base: String) -> String {
    let pathParts = path.split(separator: "/")
    let baseParts = base.split(separator: "/")
    let commonCount = zip(pathParts, baseParts)
      .prefix { $0 == $1 }
      .count
    return Array(repeating: "..", count: baseParts.count - commonCount)
      .joined(separator: "/")
      + "/"
      + pathParts.dropFirst(commonCount).joined(separator: "/")
  }
}
