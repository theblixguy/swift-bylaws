import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Layout callable types and effects")
struct LayoutEffectTests {
  @Test(
    "Named callbacks restore scope after success and failure",
    arguments: [false, true], [false, true]
  )
  func namedCallbackScope(fails: Bool, outerAllowsThrowing: Bool) async throws {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let function = function(
      expression: RuntimeExpression(
        kind: .reference(fails ? "missing" : "number"), location: location
      )
    )
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    state.synchronousClosureDepth = 2
    state.synchronousClosureAllowsThrowing = outerAllowsThrowing

    if fails {
      await #expect {
        try await evaluator.invokeSynchronous(
          function, arguments: [.integer(7)], allowsThrowing: true,
          at: location, state: &state
        )
      } throws: { error in
        (error as? RuntimeError)?.kind == .undeclaredName
      }
    } else {
      let result = try await evaluator.invokeSynchronous(
        function, arguments: [.integer(7)], allowsThrowing: true,
        at: location, state: &state
      )
      guard case let .integer(value) = result else {
        Issue.record("Named callback must return its argument")
        return
      }
      #expect(value == 7)
    }

    #expect(state.synchronousClosureDepth == 2)
    #expect(state.synchronousClosureAllowsThrowing == outerAllowsThrowing)
    #expect(state.callDepth == 0)
  }

  @Test("Named callbacks retain argument-count checks", arguments: [0, 2])
  func namedCallbackArguments(count: Int) async {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let function = function(
      expression: RuntimeExpression(
        kind: .reference("number"), location: location
      )
    )
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)

    await #expect {
      try await evaluator.invokeSynchronous(
        function, arguments: Array(repeating: .integer(7), count: count),
        allowsThrowing: true, at: location, state: &state
      )
    } throws: { error in
      (error as? RuntimeError)?.message == "'helper' takes 1 argument"
    }

    #expect(state.synchronousClosureDepth == 0)
    #expect(!state.synchronousClosureAllowsThrowing)
    #expect(state.callDepth == 0)
  }

  @Test(
    "Named callbacks retain effect checks",
    arguments: [
      (isAsync: true, allowsThrowing: false),
      (isAsync: true, allowsThrowing: true),
      (isAsync: false, allowsThrowing: false),
    ]
  )
  func namedCallbackEffects(isAsync: Bool, allowsThrowing: Bool) async {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let function = function(
      expression: RuntimeExpression(
        kind: .reference("number"),
        location: location
      ),
      isAsync: isAsync
    )
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)

    await #expect {
      try await evaluator.invokeSynchronous(
        function, arguments: [.integer(7)], allowsThrowing: allowsThrowing,
        at: location, state: &state
      )
    } throws: { error in
      (error as? RuntimeError)?.message
        == "a synchronous closure cannot call an async or throwing helper"
    }

    #expect(state.synchronousClosureDepth == 0)
    #expect(!state.synchronousClosureAllowsThrowing)
    #expect(state.callDepth == 0)
  }

  @Test(
    "Whitespace replacements reject nonthrowing helpers",
    arguments: [".none", ".space", ".newline", ".blankLine"]
  )
  func whitespaceHelper(whitespace: String) async throws {
    let project = try correctionProject(
      declarations: """
      func replace(_ source: SourceSlice) -> SourceFix.Edit {
        source.replacement(with: \(whitespace))
      }
      """,
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(
      program.errors.contains {
        $0.message.contains("a nonthrowing body cannot call a throwing API")
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Runtime whitespace overload checks callback effects")
  func runtimeWhitespace() async throws {
    let file = try FileCollector.collect(source: " \n", path: "Source.swift")
    let source = try file.source
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    state.synchronousClosureDepth = 1

    await #expect {
      try await evaluator.invoke(
        method: .replacement,
        of: .sourceSlice(source),
        arguments: RuntimeArguments(
          values: [("with", .member(.constant(.blankLine)))],
          location: location
        ),
        state: &state
      )
    } throws: { error in
      (error as? RuntimeError)?.message
        .contains("a nonthrowing body cannot call a throwing API") == true
    }
  }

  @Test("Partial multiline indentation stops portable corrections")
  func partialMultilineIndentation() async throws {
    let project = try rulesProject(
      rules: """
      Rule("indent") {
        try await app.structs.violations("Indent properties") { declaration in
          let properties = declaration.properties
          try properties.replacement {
            Indent {
              Newline()
              properties
            }
            Newline()
          }
        }
      }
      """,
      sources: [
        "Sources/Store.swift": "struct Store {\n  let text = \"\"\"\n  hello\n\"\"\"\n}",
      ]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect {
      try await rule.findings()
    } throws: { error in
      (error as? RuleError)?.description.contains(
        SourceLayoutError.inconsistentIndentation.description
      ) == true
    }
  }

  @Test("Runtime string replacement remains nonthrowing")
  func runtimeString() async throws {
    let file = try FileCollector.collect(
      source: "class Model {}",
      path: "Source.swift"
    )
    let source = try file.source
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    state.synchronousClosureDepth = 1
    let result = try await evaluator.invoke(
      method: .replacement,
      of: .sourceSlice(source),
      arguments: RuntimeArguments(
        values: [("with", .string("class Updated {}"))],
        location: location
      ),
      state: &state
    )
    let edit = try #require(
      { () -> SourceFix.Edit? in
        guard case let .sourceEdit(edit) = result else { return nil }
        return edit
      }()
    )

    #expect(edit.replacement == "class Updated {}")
  }

  @Test(
    "Layout collections take source elements",
    arguments: [
      "[attributes]",
      "[Line { attributes }]",
      "[SourceLayout { attributes }]",
    ]
  )
  func layoutCollection(expression: String) async throws {
    let project = try correctionProject(
      ruleBody: """
      try await app.classes.violations("Keep attributes") { declaration in
        let attributes = declaration.attributes
        try attributes.replacement {
          \(expression)
        }
      }
      """
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(
      program.errors.contains {
        $0.message.contains("SourceLayout takes source values")
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Layout helper return type distinguishes Line from SourceLayout")
  func primitiveReturnType() async throws {
    let project = try correctionProject(
      declarations: """
      func content(_ attributes: [Attribute]) -> SourceLayout {
        Line { attributes }
      }
      """,
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(
      program.errors.contains {
        $0.message == "'content' must return SourceLayout, not Line"
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test(
    "Stored Line factory cannot replace a SourceLayout factory",
    arguments: [
      "let output = Line(content)",
      "let output = try attributes.replacement(content)",
    ]
  )
  func primitiveClosure(expression: String) async throws {
    let project = try correctionProject(
      ruleBody: """
      try await app.classes.violations("Keep attributes") { declaration in
        let attributes = declaration.attributes
        let content = { Line { attributes } }
        \(expression)
        try attributes.replacement { attributes }
      }
      """
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(
      program.errors.contains {
        $0.message == "the layout must be SourceLayout, not Line"
      }
    )
    #expect(program.rules.isEmpty)
  }

  @Test("Line helper remains usable inside a layout builder")
  func primitiveHelper() async throws {
    let project = try correctionProject(
      declarations: """
      func content(_ attributes: [Attribute]) -> Line {
        Line { attributes }
      }
      """,
      ruleBody: """
      try await app.classes.violations("Keep attributes on one line") { declaration in
        let attributes = declaration.attributes
        try attributes.replacement {
          content(attributes)
        }
      }
      """
    )
    try project.write(
      "@MainActor @Observable class Model {}", to: "Sources/Model.swift"
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.first ?? nil)

    #expect(fix.edits.first?.replacement == "@MainActor @Observable\n")
  }

  private func function(
    expression: RuntimeExpression, isAsync: Bool = false
  ) -> RuntimeFunction {
    RuntimeFunction(
      definition: RuntimeFunctionDefinition(
        name: "helper",
        parameters: [
          .init(externalName: "value", localName: "number", type: .integer),
        ],
        returnType: .integer,
        isAsync: isAsync,
        isThrowing: true,
        body: RuntimeBody(statements: [
          RuntimeStatement(
            kind: .return(expression),
            location: expression.location
          ),
        ]),
        location: expression.location,
        access: .module
      ),
      captures: nil
    )
  }
}
