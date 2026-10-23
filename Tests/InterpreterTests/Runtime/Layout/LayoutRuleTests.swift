import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source layouts")
struct PortableLayoutRuleTests {
  @Test(
    "Attribute layouts preserve line endings and collection ordering",
    arguments: [
      (comparison: "$0.name < $1.name", expected: "@MainActor @Observable"),
      (comparison: "$0.name > $1.name", expected: "@Observable @MainActor"),
      (
        comparison: "lhs, rhs in lhs.name.count > rhs.name.count",
        expected: "@Observable @MainActor"
      ),
    ], ["\n", "\r\n", "\r"]
  )
  func attributes(
    ordering: (comparison: String, expected: String), ending: String
  ) async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.classes.violations("Order attributes") { declaration in
          if !declaration.attributes.isEmpty {
            try declaration.attributes.replacement {
              Line {
                declaration.attributes.sorted { \(ordering.comparison) }
              }
            }
          }
        }
      }
      """,
      sources: [
        "Sources/Screen.swift": "@MainActor\(ending)@Observable class Screen {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(findings.violations.count == 1)
    #expect(edit.replacement == ordering.expected + ending)
    #expect(edit.source.text == "@MainActor\(ending)@Observable ")
  }

  @Test("Attribute layouts combine loops, conditions and source arrays")
  func builderControlFlow() async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.classes.violations("Place each attribute on a line") { declaration in
          let attributes = declaration.attributes
          if attributes.count > 1 {
            try attributes.replacement {
              if false {
                BlankLine()
              }
              for attribute in attributes.reversed() {
                Line { [attribute] }
              }
            }
          }
        }
      }
      """,
      sources: [
        "Sources/Screen.swift": "@MainActor @Observable class Screen {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(
      findings.violations.fixes.first??.edits.first?
        .replacement == "@Observable\n@MainActor\n"
    )
  }

  @Test("Attribute predicates check every matching attribute")
  func repeatedAttributes() async throws {
    let project = try rulesProject(
      rules: """
      Rule("labels") {
        try await app.classes.violations(of: Matcher<Class>("Have requested label") { declaration in
          declaration.hasAttribute("@Label", argument: { $0.stringValue == "second" })
        })
      }
      """,
      sources: [
        "Sources/Screen.swift": "@Label(\"first\") @Label(\"second\") class Screen {}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test("Property grouping uses attribute argument predicates")
  func propertyGroups() async throws {
    let project = try rulesProject(
      rules: #"""
      Rule("properties") {
        try await app.syntaxNodes(of: .structDeclaration)
          .violations("Group environment, state and constants") { declaration in
            let properties = declaration.members
            let environment = properties.filter { $0.hasAttribute("Environment") }
            let constants = properties.filter {
              $0.property?.isConstant == true && $0.attributes.isEmpty
            }
            if !properties.isEmpty {
              try properties.replacement {
                environment.filter {
                  $0.hasAttribute("Environment", argument: \.isKeyPath)
                }
                environment.filter {
                  !$0.hasAttribute("Environment", argument: \.isKeyPath)
                }
                BlankLine()
                properties.filter { $0.hasAttribute("State") }
                BlankLine()
                constants.filter { $0.property?.visibility == .private }
                constants.filter { $0.property?.visibility != .private }
              }
            }
          }
      }
      """#,
      sources: [
        "Sources/Panel.swift": #"""
        struct Panel {
          let onClose: () -> Void
          @State private var query = ""
          @Environment(Settings.self) private var settings
          private let store: Store
          @Environment(\.locale) private var locale
        }
        """#,
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(
      applying(edit) == #"""
      struct Panel {
        @Environment(\.locale) private var locale
        @Environment(Settings.self) private var settings

        @State private var query = ""

        private let store: Store
        let onClose: () -> Void
      }
      """#
    )
  }

  @Test("Call layouts compose nested array corrections")
  func nestedArguments() async throws {
    let project = try rulesProject(
      rules: """
      Rule("calls") {
        try await app.calls.named("log").violations("Wrap labelled arguments") { call in
          let leading = call.arguments.prefix { $0.label == nil }
          try call.arguments.replacement {
            Line { leading }
            for argument in call.arguments.dropFirst(leading.count) {
              if let elements = argument.expression?.arrayElements {
                try elements.replacement {
                  for element in elements {
                    Line { element }
                  }
                }
              } else {
                Line { argument }
              }
            }
            Newline()
          }
        }
      }
      """,
      sources: [
        "Sources/Log.swift":
          #"let result = log(.info, "Ready", category: "Transfer", tags: ["ready", "cached"])"#,
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(
      applying(edit) == """
      let result = log(
        .info, "Ready",
        category: "Transfer",
        tags: [
          "ready",
          "cached"
        ]
      )
      """
    )
  }

  @Test(
    "Spacing corrections preserve line endings and disappear after correction",
    arguments: ["\n", "\r\n", "\r"]
  )
  func whitespace(ending: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("spacing") {
        try await app.functions.named("second").violations("Separate functions") { function in
          try function.spacing.before.replacement(with: .blankLine)
        }
      }
      """,
      sources: [
        "Sources/Calls.swift": "func first() {}\(ending)func second() {}\(ending)",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(edit.source.text == ending)
    #expect(edit.replacement == ending + ending)
    let path = project.fileURL(for: "Sources/Calls.swift")
    try "func first() {}\(ending)\(ending)func second() {}\(ending)".write(
      to: path,
      atomically: true,
      encoding: .utf8
    )
    await CodebaseCache.shared.removeEntries(under: project.rootURL.path)
    let updatedProgram = try await loadedProgram(in: project)
    let verified = try await #require(updatedProgram.rules.first).findings()
    #expect(verified.violations.isEmpty)
  }

  @Test("Wrapping aligns arguments with the first inline argument")
  func alignedWrapping() async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Wrap arguments at 30 characters") { call in
          try call.arguments.replacement {
            Align { Wrap(width: 30) { call.arguments } }
          }
        }
      }
      """,
      sources: [
        "Sources/Call.swift": "let value = send(first: 1, second: 2, third: 3)",
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(
      applying(edit)
        ==
        "let value = send(first: 1,\n                 second: 2,\n                 third: 3)"
    )
  }

  @Test("Optional breaks retain default width inside an indented layout")
  func indentedWrapping() async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Indent arguments") { call in
          try call.arguments.replacement {
            Indent {
              Newline()
              Wrap(width: nil) {
                for argument in call.arguments {
                  argument
                  Break()
                }
              }
            }
            Newline()
          }
        }
      }
      """,
      sources: ["Sources/Call.swift": "let value = send(first: 1, second: 2)"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(applying(edit) == "let value = send(\n    first: 1, second: 2\n)")
  }

  @Test("Layout builders reject text without captured source")
  func unbackedText() async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.classes.violations("Keep attributes") { declaration in
          try declaration.attributes.replacement {
            Line { "@Observable" }
          }
        }
      }
      """,
      sources: ["Sources/Screen.swift": "@Observable class Screen {}"]
    )
    let program =
      await RuleProgram
        .loaded(fromFiles: [project.fileURL(for: "ProjectRules.swift").path])

    #expect(program.rules.isEmpty)
    #expect(
      program.errors
        .contains { $0.message.contains("SourceLayout takes source values") }
    )
  }

  @Test("Statement layouts use adjacent source elements")
  func statementSpacing() async throws {
    let project = try rulesProject(
      rules: """
      Rule("statements") {
        try await app.syntaxNodes(of: .codeBlock).violations("Separate bindings and calls") { block in
          let statements = block.statements
          if !statements.isEmpty {
            try statements.replacement {
              for index in statements.indices {
                if index > statements.startIndex {
                  let previous = statements[index - 1]
                  let current = statements[index]
                  let previousBinding = previous.kind == .variableDeclaration
                  let currentBinding = current.kind == .variableDeclaration
                  let previousCall = previous.kind == .functionCall
                    || previous.descendants.contains { $0.kind == .functionCall }
                  let currentCall = current.kind == .functionCall
                    || current.descendants.contains { $0.kind == .functionCall }
                  let previousTry = previous.kind == .tryExpression
                    || previous.descendants.contains { $0.kind == .tryExpression }
                  let currentTry = current.kind == .tryExpression
                    || current.descendants.contains { $0.kind == .tryExpression }
                  if previousBinding && currentCall
                    || currentBinding && previousCall
                    || previousTry && (currentBinding || currentCall)
                    || currentTry && (previousBinding || previousCall) {
                    BlankLine()
                  }
                }
                statements[index]
              }
            }
          }
        }
      }
      """,
      sources: [
        "Sources/Refresh.swift": """
        func refresh() async throws {
          let request = try makeRequest()
          await log(request)
          try await save(request)
          let count = 1
          let limit = 2
        }
        """,
      ]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    let edit = try #require(findings.violations.fixes.first??.edits.first)

    #expect(
      applying(edit) == """
      func refresh() async throws {
        let request = try makeRequest()

        await log(request)

        try await save(request)

        let count = 1
        let limit = 2
      }
      """
    )
  }

  @Test("Layout and correction helpers retain their callable types")
  func helpers() async throws {
    let project = try rulesProject(
      rules: """
      Rule("attributes") {
        try await app.classes.violations("Order attributes", changes: corrections)
      }
      """,
      sources: [
        "Sources/Screen.swift": "@MainActor @Observable class Screen {}",
      ]
    )
    let path = project.fileURL(for: "ProjectRules.swift")
    let source = try String(contentsOf: path, encoding: .utf8)
    try
      ("""
      func corrections(_ declaration: Class) throws -> [SourceFix.Edit] {
        let attributes = declaration.attributes
        let body = { SourceLayout { Line { attributes.reversed() } } }
        return [try attributes.replacement(body)]
      }

      """ + source).write(to: path, atomically: true, encoding: .utf8)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(
      findings.violations.fixes.first??.edits.first?
        .replacement == "@Observable @MainActor\n"
    )
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
