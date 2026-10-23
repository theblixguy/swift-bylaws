import Bylaws
import BylawsCore
import Testing

@Suite("Source layout rules")
struct LayoutRuleTests {
  @Test("Attribute rule orders attributes on one line")
  func attributeOrder() async throws {
    let source = "@MainActor\n@Observable class Screen {}"
    let codebase = Codebase(root: .sources(["Sources/Screen.swift": source]))
    let violations = try await codebase.classes
      .violations("Place Observable first") { declaration in
        try declaration.attributes.replacement {
          Line {
            declaration.attributes.sorted { lhs, rhs in
              lhs.name == "Observable" && rhs.name != "Observable"
            }
          }
        }
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(violations.checkedCount == 1)
    #expect(violations.offenders.map(\.name) == ["Screen"])
    #expect(Self.applying(edit) == "@Observable @MainActor\nclass Screen {}")
    #expect(edit.source.file.text == source)
  }

  @Test("Property rule emits groups without changing property contents")
  func propertyGroups() async throws {
    let source = #"""
    struct Panel {
      let onClose: () -> Void
      @State private var query = ""
      @Environment(Settings.self) private var settings
      private let store: Store
      @Environment(\.locale) private var locale
    }
    """#
    let codebase = Codebase(root: .sources(["Sources/Panel.swift": source]))
    let violations = try await codebase.syntaxNodes(of: .structDeclaration)
      .violations("Group environment, state and constants") { declaration in
        let properties = declaration.members
        let environment = properties.filter { $0.hasAttribute("Environment") }
        let constants = properties.filter {
          $0.property?.isConstant == true && $0.attributes.isEmpty
        }
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
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(Self.applying(edit) == #"""
    struct Panel {
      @Environment(\.locale) private var locale
      @Environment(Settings.self) private var settings

      @State private var query = ""

      private let store: Store
      let onClose: () -> Void
    }
    """#)
    #expect(edit.source.file.text == source)
  }

  @Test("Statement rule separates bindings, calls and throwing calls")
  func statementSpacing() async throws {
    let source = """
    func refresh() async throws {
      let request = try makeRequest()
      await log(request)
      try await save(request)
      let count = 1
      let limit = 2
    }
    """
    let codebase = Codebase(root: .sources(["Sources/Refresh.swift": source]))
    let violations = try await codebase.syntaxNodes(of: .codeBlock)
      .violations("Separate bindings and throwing calls") { block in
        let statements = block.statements
        try statements.replacement {
          for index in statements.indices {
            if index > statements.startIndex {
              let previous = statements[index - 1]
              let current = statements[index]
              let previousIsBinding = previous.kind == .variableDeclaration
              let currentIsBinding = current.kind == .variableDeclaration
              let previousHasCall = previous.kind == .functionCall
                || previous.descendants.contains { $0.kind == .functionCall }
              let currentHasCall = current.kind == .functionCall
                || current.descendants.contains { $0.kind == .functionCall }
              let previousHasTry = previous.kind == .tryExpression
                || previous.descendants.contains { $0.kind == .tryExpression }
              let currentHasTry = current.kind == .tryExpression
                || current.descendants.contains { $0.kind == .tryExpression }
              if previousIsBinding && currentHasCall
                || currentIsBinding && previousHasCall
                || previousHasTry && (currentIsBinding || currentHasCall)
                || currentHasTry && (previousIsBinding || previousHasCall)
              {
                BlankLine()
              }
            }
            statements[index]
          }
        }
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(Self.applying(edit) == """
    func refresh() async throws {
      let request = try makeRequest()

      await log(request)

      try await save(request)

      let count = 1
      let limit = 2
    }
    """)
    #expect(edit.source.file.text == source)
  }

  @Test("Call rule keeps leading arguments together and expands array argument")
  func callArguments() async throws {
    let source = #"""
    func record() {
      logger.write(.info, "Ready", category: "Transfer", tags: ["ready", "cached"])
    }
    """#
    let codebase = Codebase(root: .sources(["Sources/Log.swift": source]))
    let violations = try await codebase.calls.named("logger.write")
      .violations("Wrap labelled arguments") { call in
        let leading = call.arguments.prefix { $0.label == nil }
        try call.arguments.replacement {
          Line { leading }
          for argument in call.arguments.dropFirst(leading.count) {
            if let elements = argument.expression?.arrayElements,
               !elements.isEmpty
            {
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
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(Self.applying(edit) == """
    func record() {
      logger.write(
        .info, "Ready",
        category: "Transfer",
        tags: [
          "ready",
          "cached"
        ]
      )
    }
    """)
    #expect(edit.source.file.text == source)
  }

  private static func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
