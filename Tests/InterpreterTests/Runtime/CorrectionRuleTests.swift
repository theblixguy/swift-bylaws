import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source corrections")
struct CorrectionRuleTests {
  @Test("Declared rules and overrides call helpers that attach fixes")
  func hiddenHelperRules() async throws {
    let helper = """
    func corrected(_ app: Codebase, _ name: String) async throws -> Violations<Class> {
      return try await app.classes.violations(of: .isFinal).withFix { context in
        try context.offender.nameSource.replacement(with: name)
      }
    }
    """
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      \(helper)
      Rule("names") { try await corrected(app, "RootFixed") }
      """,
      "Sources/Child/Bylaws.swift": """
      let app = Codebase(including: ["**"])
      \(helper)
      Override("names", reason: "Child names differ") {
        try await corrected(app, "ChildFixed")
      }
      """,
      "Sources/Root.swift": "class Root {}",
      "Sources/Child/Child.swift": "class Child {}",
    ])
    let program = try await discoveredProgram(in: project)
    try #require(program.rules.count == 2)
    let parent = try await program.rules[0].findings()
    let child = try await program.rules[1].findings()

    #expect(parent.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["RootFixed"])
    #expect(child.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["ChildFixed"])
  }

  @Test(
    "Malformed runtime bodies preserve successful legacy rules",
    arguments: [
      "true", "let selection = app.classes; return true",
      "try await missing(app)",
    ]
  )
  func malformedRuntimeBody(body: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("valid") { app.classes.violations(of: .isFinal) }
      Rule("broken") { \(body) }
      """,
      "Sources/Model.swift": "final class Model {}",
    ])
    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(!program.errors.isEmpty)
    #expect(program.rules.map(\.id.rawValue) == ["valid"])
    #expect(program.errors.allSatisfy {
      $0.location.filePath == project.fileURL(for: "Bylaws.swift").path
        && $0.location.line == 3
    })
  }

  @Test("Declared rules and overrides share runtime fix API")
  func declaredRules() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("names") {
        let classes = try await app.classes
        try await classes.violations(of: .isFinal).withFix { context in
          try context.offender.nameSource.replacement(with: "RootFixed")
        }
      }
      """,
      "Sources/Child/Bylaws.swift": """
      let app = Codebase(including: ["**"])
      Override("names", reason: "Child names differ") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try context.offender.nameSource.replacement(with: "ChildFixed")
        }
      }
      """,
      "Sources/Root.swift": "class Root {}",
      "Sources/Child/Child.swift": "class Child {}",
    ])
    let program = try await discoveredProgram(in: project)
    try #require(program.rules.count == 2)
    let parent = try await program.rules[0].findings()
    let child = try await program.rules[1].findings()

    #expect(parent.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.source.text) == ["Root"])
    #expect(child.violations.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.source.text) == ["Child"])
    #expect(program.rules[0].origin == Rule.Origin(
      filePath: project.fileURL(for: "Bylaws.swift").path, ruleID: "names"
    ))
    #expect(program.rules[1].origin == Rule.Origin(
      filePath: project.fileURL(for: "Sources/Child/Bylaws.swift").path,
      ruleID: "names"
    ))
  }

  @Test("Compiled and portable regex fixes select same bytes")
  func regexParity() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("hex") {
        try await app.syntaxNodes(of: .integerLiteral)
          .violations(matching: Matcher<SourceNode>("contain lowercase hex digits") {
            $0.text.hasPrefix("0x") && $0.text.contains(/[a-f]+/)
          })
          .withFix { context in
            for part in try context.source.matches(of: /[a-f]+/) {
              part.replacement(with: part.text.uppercased())
            }
          }
      }
      """#,
      sources: [
        "Sources/Values.swift": "let café = 0xaf\nlet other = 0xb2\nlet binary = 0b101\n",
      ]
    )
    let program = try await loadedProgram(in: project)
    let interpreted = try await #require(program.rules.first).findings()
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"]
    )
    let compiled = try await codebase.syntaxNodes(of: .integerLiteral)
      .violations(
        matching: Matcher<SourceNode>("contain lowercase hex digits") {
          $0.text.hasPrefix("0x") && $0.text.contains(/[a-f]+/)
        }
      )
      .withFix { context in
        for part in try context.source.matches(of: /[a-f]+/) {
          part.replacement(with: part.text.uppercased())
        }
      }

    #expect(interpreted.violations.fixes == compiled.fixes)
    let edits = interpreted.violations.fixes.compactMap(\.self).flatMap(\.edits)
    #expect(edits.map(\.source.text) == ["af", "b"])
    #expect(edits.map(\.replacement) == ["AF", "B"])
    #expect(edits.first?.source.range.lowerBound == "let café = 0x".utf8.count)
  }

  @Test("Fix closure queries codebase and edits another file")
  func crossFileContext() async throws {
    let project = try rulesProject(
      rules: """
      Rule("names") {
        try await app.classes.named("Primary")
          .violations(matching: Matcher<Class>("match") { _ in true })
          .withFix("Rename paired classes") { context in
            let companions = try await context.codebase.classes.named("Companion")
            let companion = try companions.only()
            try context.offender.nameSource.replacement(with: "Main")
            try companion.nameSource.replacement(with: "Helper")
          }
      }
      """,
      sources: [
        "Sources/Primary.swift": "class Primary {}",
        "Sources/Companion.swift": "class Companion {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.compactMap(\.self).first)

    #expect(fix.title == "Rename paired classes")
    #expect(fix.edits.map(\.source.text) == ["Primary", "Companion"])
    #expect(Set(fix.edits.map(\.source.filePath)).count == 2)
  }

  @Test("Unique selection rejects absent and repeated companions", arguments: [
    "", "class Companion {}\nclass Companion {}",
  ])
  func uniqueCompanion(source: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("paired") {
        try await app.classes.named("Primary").violations(of: .isFinal)
          .withFix { context in
            let companions = try await context.codebase.classes.named("Companion")
            let companion = try companions.only()
            try companion.nameSource.replacement(with: "Helper")
          }
      }
      """,
      sources: [
        "Sources/Primary.swift": "class Primary {}",
        "Sources/Companion.swift": source,
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: (any Error).self) { try await rule.findings() }
  }

  @Test("Call projections keep identifier label and expression targets")
  func callProjections() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("calls") {
        try await app.calls.violations(matching: .references("save"))
          .withFix { context in
            let call = context.offender
            let argument = try call.argument(labeled: "old")
            try call.memberNameSource.replacement(with: "store")
            try argument.expressionSource.replacement(with: "\"new\"")
            if let label = try argument.labelSource {
              label.replacement(with: "updated")
            }
          }
      }
      """#,
      sources: ["Sources/Call.swift": #"func run() { save(old: "old") }"#]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edits = try #require(findings.violations.fixes.compactMap(\.self).first)
      .edits

    #expect(edits.map(\.source.text) == ["save", #""old""#, "old"])
    #expect(edits.map(\.replacement) == ["store", #""new""#, "updated"])
  }

  @Test("Body slices keep relative UTF8 ranges and file context")
  func bodySlice() async throws {
    let project = try rulesProject(
      rules: """
      Rule("body") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          let body = try context.offender.bodySource
          let target = try body.slice(1..<4)
          if target.file.text.contains("café") {
            target.replacement(with: "var")
          }
        }
      }
      """,
      sources: ["Sources/Model.swift": "class Model { let café = 1 }"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.compactMap(\.self)
      .first?.edits.first)

    #expect(edit.source.text == "let")
    #expect(edit.source.range == 14..<17)
    #expect(edit.replacement == "var")
  }

  @Test("Named fix helper keeps typed context")
  func namedHelper() async throws {
    let project = try TemporaryProject(files: [
      "ProjectRules.swift": """
      func rename(_ context: FixContext<Class>) async throws -> [SourceFix.Edit] {
        return [try context.offender.nameSource.replacement(with: "Updated")]
      }
      let app = Codebase(including: ["Sources/**"])
      let rules = [Rule("helper") {
        try await app.classes.violations(of: .isFinal).withFix(rename)
      }]
      """,
      "Sources/Model.swift": "class Model {}",
    ])
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.fixes.compactMap(\.self).first?.edits.first?
      .replacement == "Updated")
  }

  @Test("Unique selector rejects absent and repeated targets", arguments: [
    "missing", "Model",
  ])
  func uniqueTarget(pattern: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("unique") {
        try await app.classes.violations(matching: Matcher<Class>("match") { _ in true })
          .withFix { context in
            let target = try context.file.matches(of: /\(pattern)/).only()
            target.replacement(with: "Updated")
          }
      }
      """,
      sources: ["Sources/Model.swift": "class Model { let name = \"Model\" }"]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: (any Error).self) { try await rule.findings() }
  }

  @Test("Raw regex delimiters preserve slash matching")
  func rawRegex() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("raw") {
        try await app.classes.violations(matching: Matcher<Class>("match") { _ in true })
          .withFix { context in
            let target = try context.file.matches(of: #/usr/local/#).only()
            target.replacement(with: "opt/local")
          }
      }
      """#,
      sources: [
        "Sources/Model.swift": "class Model { let path = \"usr/local\" }",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.fixes.compactMap(\.self).first?.edits.first?
      .source
      .text == "usr/local")
  }

  @Test("Multiline regex reports supported literal form")
  func multilineRegex() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("multiline") {
        try await app.classes.violations(matching: Matcher<Class>("match") {
          $0.name.contains(#/
            Model
          /#)
        })
      }
      """#,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = await RuleProgram
      .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

    #expect(program.errors.contains { $0.message.contains("multiline regex") })
  }
}
