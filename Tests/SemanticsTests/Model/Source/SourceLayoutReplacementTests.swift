import BylawsSemantics
import Foundation
import Testing

@Suite("Source layout replacements")
struct SourceLayoutReplacementTests {
  @Test("Attribute ordering retains declaration boundary")
  func attributes() throws {
    let file =
      try collect("@MainActor\n@Observable public final class Store {}")
    let declaration = try #require(file.classes.first)
    let attributes = declaration.attributes
    let edit = try attributes.replacement {
      Line {
        attributes.sorted { $0.name > $1.name }
      }
    }
    #expect(applying(edit) ==
      "@Observable @MainActor\npublic final class Store {}")
    #expect(try attributes.first?.source.text == "@MainActor")
  }

  @Test("Attribute argument queries retain source")
  func attributeArguments() throws {
    let file =
      try collect(
        #"struct Screen { @Environment(\.locale) var locale; @Environment(Settings.self) var settings }"#
      )
    let properties = file.structs[0].properties
    let isKeyPath = properties[0].hasAttribute(
      "Environment",
      argument: \.isKeyPath
    )
    #expect(isKeyPath)
    let isType = !properties[1].hasAttribute(
      "Environment",
      argument: \.isKeyPath
    )
    #expect(isType)
    let attribute = properties[0].attributes[0]
    #expect(try attribute.argument?.source.text == #"\.locale"#)
    let decoded = try JSONDecoder().decode(
      Attribute.self,
      from: JSONEncoder().encode(attribute)
    )
    #expect(decoded == attribute)
    #expect(throws: SourceError.unavailable) { try decoded.source }
    #expect(decoded.argument == nil)
  }

  @Test("Attribute predicates check every matching attribute")
  func repeatedAttributes() throws {
    let file =
      try collect("@Label(\"first\") @Label(\"second\") class Store {}")
    let declaration = try #require(file.classes.first)
    let matches = declaration.hasAttribute(
      "@Label",
      argument: { $0.stringValue == "second" }
    )
    #expect(matches)
  }

  @Test("Property layouts include binding specifiers and attributes")
  func propertyGroups() throws {
    let file = try collect(
      """
      struct Screen {
        let completion: () -> Void
        @State var count = 0
        private let store: Store
        @Environment(Settings.self) var settings
        @Environment(\\.locale) var locale
      }
      """
    )
    let properties = file.structs[0].properties
    let edit = try properties.replacement {
      properties
        .filter { $0.hasAttribute("Environment", argument: \.isKeyPath) }
      properties.filter {
        $0.hasAttribute("Environment")
          && !$0.hasAttribute(
            "Environment",
            argument: \.isKeyPath
          )
      }
      BlankLine()
      properties.filter { $0.hasAttribute("State") }
      BlankLine()
      properties.filter { $0.isConstant && $0.visibility == .private }
      properties.filter { $0.isConstant && $0.visibility != .private }
    }
    #expect(
      applying(edit) == """
      struct Screen {
        @Environment(\\.locale) var locale
        @Environment(Settings.self) var settings

        @State var count = 0

        private let store: Store
        let completion: () -> Void
      }
      """
    )
  }

  @Test("Member layouts support custom comparisons")
  func members() throws {
    let file = try collect(
      """
      struct Store {
        func zebra() {}
        let count: Int
        func apple() {}
      }
      """
    )
    let declaration = try #require(
      file.syntaxNodes(of: .structDeclaration)
        .first
    )
    let members = declaration.members
    #expect(members.map(\.name) == ["zebra", "count", "apple"])
    #expect(members[1].property?.isConstant == true)
    let edit = try members.replacement {
      members.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    #expect(
      applying(edit) == """
      struct Store {
        func apple() {}
        let count: Int
        func zebra() {}
      }
      """
    )
  }

  @Test("Statement layouts insert conditional blank lines")
  func statements() throws {
    let file = try collect(
      """
      func update() {
        let request = try prepare()
        log(request)
        try save(request)
      }
      """
    )
    let block = try #require(file.syntaxNodes(of: .codeBlock).first)
    let statements = block.statements
    let edit = try statements.replacement {
      for statement in statements {
        if statement != statements.first {
          BlankLine()
        }
        statement
      }
    }
    #expect(
      applying(edit) == """
      func update() {
        let request = try prepare()

        log(request)

        try save(request)
      }
      """
    )
  }

  @Test("Argument layouts preserve labels and regenerate commas")
  func arguments() throws {
    let file =
      try collect(
        "let result = log(.info, \"Finished\", category: \"Sync\", count: 2)"
      )
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement {
      Line { arguments.prefix(2) }
      for argument in arguments.dropFirst(2) {
        Line { argument }
      }
    }
    #expect(
      applying(edit) == """
      let result = log(
        .info, "Finished",
        category: "Sync",
        count: 2
      )
      """
    )
  }

  @Test("Aligned wrapping retains first argument after delimiter")
  func hangingArguments() throws {
    let file = try collect("let result = send(first: 1, second: 2, third: 3)")
    let arguments = try #require(file.calls.first).arguments
    let edit = try arguments.replacement {
      Align {
        Wrap(width: 36) { arguments }
      }
    }
    #expect(
      applying(edit)
        ==
        "let result = send(first: 1,\n                  second: 2,\n                  third: 3)"
    )
  }

  @Test("Nested layout edits retain complete parent arguments")
  func nestedEdits() throws {
    let file = try collect("let result = send(values: [2, 1], count: 2)")
    let arguments = try #require(file.calls.first).arguments
    let array = try #require(arguments[0].expression?.arrayElements)
    let arrayEdit = try array.replacement {
      for element in array.reversed() {
        Line { element }
      }
    }
    let edit = try arguments.replacement {
      Newline()
      arrayEdit
      Line { arguments[1] }
    }
    #expect(
      applying(edit) == """
      let result = send(
        values: [
          1,
          2
        ],
        count: 2
      )
      """
    )
  }

  @Test("Dictionary layouts retain key-value pairs")
  func dictionary() throws {
    let file = try collect("let values = [\"z\": 1, \"a\": 2]")
    let expression = try #require(file.variableBindings[0].initialValue)
    let elements = try #require(expression.dictionaryElements)
    let edit = try elements.replacement {
      elements.sorted { $0.key.text < $1.key.text }
    }
    #expect(applying(edit) == "let values = [\"a\": 2, \"z\": 1]")
  }

  @Test("Missing and repeated output elements stop replacement")
  func inventory() throws {
    let file = try collect("@MainActor @Observable class Store {}")
    let attributes = file.classes[0].attributes
    #expect(throws: SourceLayoutReplacementError.missingElement) {
      try attributes.replacement { attributes[0] }
    }
    #expect(throws: SourceLayoutReplacementError.repeatedElement) {
      try attributes.replacement {
        attributes
        attributes[0]
      }
    }
  }

  @Test("Foreign elements and source snapshots stop replacement")
  func foreignSources() throws {
    let file =
      try collect("@MainActor class Store {}\n@Observable class Other {}")
    #expect(throws: SourceLayoutReplacementError.foreignElement) {
      try file.classes[0].attributes.replacement { file.classes[1].attributes }
    }
    let other = try FileCollector.collect(
      source: "@MainActor class Store {}",
      path: "/virtual/Other.swift"
    )
    #expect(throws: SourceLayoutReplacementError.differentSnapshots) {
      try file.classes[0].attributes.replacement { other.classes[0].attributes }
    }
  }

  @Test("Intervening members and conditional branches stop replacement")
  func listBoundaries() throws {
    let file =
      try collect(
        "struct Store { let first: Int\nfunc run() {}\nlet second: Int }"
      )
    let properties = file.structs[0].properties
    #expect(throws: SourceLayoutReplacementError.noncontiguousElements) {
      try properties.replacement { properties.reversed() }
    }
    let conditional = try collect(
      """
      struct Store {
        let first: Int
        #if DEBUG
        let second: Int
        #endif
      }
      """
    )
    let members = conditional.syntaxNodes(of: .structDeclaration)[0].members
    #expect(throws: SourceLayoutReplacementError.conditionalCompilation) {
      try members.replacement { members }
    }
  }

  @Test("Leading comments remain attached during ordering")
  func leadingComments() throws {
    let file = try collect(
      """
      struct Store {
        /// The last item.
        let zebra: Int
        /// The first item.
        let apple: Int
      }
      """
    )
    let properties = file.structs[0].properties
    let edit =
      try properties
        .replacement { properties.sorted { $0.name < $1.name } }
    #expect(
      applying(edit) == """
      struct Store {
        /// The first item.
        let apple: Int
        /// The last item.
        let zebra: Int
      }
      """
    )
  }

  @Test("Inline comments stop attribute joining")
  func inlineComments() throws {
    let file =
      try collect(
        "@MainActor // Keep the declaration isolated.\n@Observable class Store {}"
      )
    let attributes = file.classes[0].attributes
    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try attributes.replacement { Line { attributes } }
    }
  }

  @Test("Statement lists retain operator expressions")
  func operatorStatements() throws {
    let file = try collect("func update() {\n  count += 1\n  send()\n}")
    let statements = file.syntaxNodes(of: .codeBlock)[0].statements
    #expect(statements.count == 2)
    #expect(statements[0].expression?.text == "count += 1")
    let edit = try statements.replacement {
      statements[0]
      BlankLine()
      statements[1]
    }
    #expect(applying(edit) == "func update() {\n  count += 1\n\n  send()\n}")
  }

  @Test("Enum cases retain declarations and individual elements")
  func enumCases() throws {
    let file =
      try collect("enum Status {\n  case zebra, apple\n  case middle\n}")
    let declaration = file.syntaxNodes(of: .enumDeclaration)[0]
    #expect(declaration.members.count == 2)
    let cases = declaration.cases[0].cases
    #expect(cases.map(\.name) == ["zebra", "apple"])
    let edit =
      try cases
        .replacement { cases.sorted { ($0.name ?? "") < ($1.name ?? "") } }
    #expect(applying(edit) ==
      "enum Status {\n  case apple, zebra\n  case middle\n}")
  }

  @Test("Modifier ordering retains declaration spacing")
  func modifiers() throws {
    let file = try collect("final public class Store {}")
    let modifiers = file.syntaxNodes(of: .classDeclaration)[0].modifiers
    #expect(modifiers.map(\.name) == ["final", "public"])
    let edit = try modifiers.replacement { modifiers.reversed() }
    #expect(applying(edit) == "public final class Store {}")
  }

  @Test("Parameter layouts retain labels and types")
  func parameters() throws {
    let file = try collect("func send(_ value: Int, count: Int) {}")
    let parameters = file.syntaxNodes(of: .functionDeclaration)[0].parameters
    #expect(parameters.map(\.name) == ["value", "count"])
    let edit = try parameters.replacement {
      for parameter in parameters { Line { parameter } }
    }
    #expect(applying(edit) == "func send(\n  _ value: Int,\n  count: Int\n) {}")
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Layout.swift")
  }

  private func applying(_ edit: SourceFix.Edit) -> String {
    var bytes = Array(edit.source.file.text.utf8)
    bytes.replaceSubrange(edit.source.range, with: edit.replacement.utf8)
    return String(decoding: bytes, as: UTF8.self)
  }
}
