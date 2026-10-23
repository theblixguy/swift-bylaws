import BylawsCore
import BylawsSemantics
import Testing
@testable import BylawsInterpreter

@Suite("Correction effects")
struct CorrectionEffectTests {
  @Test("Throwing helper queries codebase inside fix closure")
  func throwingHelper() async throws {
    let project = try correctionProject(
      declarations: """
      func rename(_ context: FixContext<Class>) async throws -> [SourceFix.Edit] {
        let classes = try await context.codebase.classes
        let target = try classes.only()
        return [try target.nameSource.replacement(with: "Updated")]
      }
      """,
      ruleBody: "try await app.classes.violations(of: .isFinal).withFix(rename)"
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.compactMap(\.self).first?
      .edits.first)

    #expect(edit.source.text == "Model")
    #expect(edit.replacement == "Updated")
  }

  @Test(
    "Matcher rejects throwing projections with or without try",
    arguments: ["", "try "]
  )
  func matcherProjection(prefix: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.properties.violations(matching: Matcher<Property>("have body") {
      \(prefix)$0.bodySource.text.contains("get")
    })
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "a nonthrowing body cannot call a throwing API",
      atLine: 6
    )
  }

  @Test(
    "Collection rejects throwing inline and key path projections",
    arguments: [
      "{ $0.bodySource.text }", "{ try $0.bodySource.text }",
      "\\.bodySource.text",
    ]
  )
  func collectionProjection(transform: String) async throws {
    let project = try correctionProject(ruleBody: """
    let values = try await app.properties
    let texts = values.map(\(transform))
    try await app.classes.violations(of: .isFinal)
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "a nonthrowing body cannot call a throwing API",
      atLine: 6
    )
  }

  @Test("Stored collection closure retains inferred throwing effect")
  func storedProjection() async throws {
    let project = try correctionProject(
      declarations: "let read = { (value: Property) -> String in value.bodySource.text }",
      ruleBody: """
      let values = try await app.properties
      let texts = values.map(read)
      try await app.classes.violations(of: .isFinal)
      """
    )

    await expectCorrectionRejection(
      in: project,
      containing: "the collection closure must be synchronous and nonthrowing",
      atLine: 6
    )
  }

  @Test("Stored throwing closure cannot run inside collection callback")
  func storedProjectionCall() async throws {
    let project = try correctionProject(
      declarations: "let read = { (value: Property) -> String in value.bodySource.text }",
      ruleBody: """
      let values = try await app.properties
      let texts = values.map { read($0) }
      try await app.classes.violations(of: .isFinal)
      """
    )

    await expectCorrectionRejection(
      in: project, containing: "a nonthrowing body cannot call a throwing API",
      atLine: 6
    )
  }

  @Test(
    "Helper declaration must allow query suspension",
    arguments: [false, true]
  )
  func helperSuspension(isAsync: Bool) async throws {
    let project = try correctionProject(
      declarations: """
      func count(_ codebase: Codebase) \(isAsync ? "async " : "")throws -> Int {
        let values = try await codebase.classes
        return values.count
      }
      """,
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )

    if isAsync {
      let program = try await loadedProgram(in: project)
      let findings = try await #require(program.rules.first).findings()
      #expect(findings.violations.count == 1)
    } else {
      await expectCorrectionRejection(
        in: project, containing: "a synchronous body cannot call an async API",
        atLine: 4
      )
    }
  }

  @Test(
    "Nonthrowing helper cannot hide throwing projection",
    arguments: ["", "try "]
  )
  func nonthrowingHelper(prefix: String) async throws {
    let project = try correctionProject(
      declarations: "func read(_ value: Property) -> String { \(prefix)value.bodySource.text }",
      ruleBody: """
      try await app.properties.violations(matching: Matcher<Property>("have body") {
        read($0).contains("get")
      })
      """
    )

    await expectCorrectionRejection(
      in: project,
      containing: "a nonthrowing body cannot call a throwing API",
      atLine: 3
    )
  }

  @Test("Pure collection callbacks retain source text transforms")
  func pureTransform() async throws {
    let project = try correctionProject(ruleBody: #"""
    try await app.classes.violations(of: .isFinal).withFix { context in
      let source = try context.offender.nameSource
      let edits = [source].map { $0.replacement(with: $0.text.uppercased()) }
      edits
    }
    """#)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let edit = try #require(findings.violations.fixes.compactMap(\.self).first?
      .edits.first)

    #expect(edit.source.text == "Model")
    #expect(edit.replacement == "MODEL")
  }

  @Test(
    "Runtime property dispatch rejects throwing callback access before reading source"
  )
  func runtimePropertyEffect() async throws {
    let file = try FileCollector.collect(
      source: "class Model { var value = 1 }",
      path: "Model.swift"
    )
    let property = try #require(file.classes.first?.properties.first)
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    state.synchronousClosureDepth = 1

    await #expect {
      try await evaluator.member(
        named: .bodySource,
        of: .model(.property(property)),
        at: location,
        state: &state
      )
    } throws: { error in
      guard let error = error as? RuntimeError else { return false }
      return error.location == location && error.message
        .contains("a nonthrowing body cannot call a throwing API")
    }
  }

  @Test(
    "Runtime method dispatch rejects throwing callback access before slicing"
  )
  func runtimeMethodEffect() async throws {
    let file = try FileCollector.collect(
      source: "class Model {}",
      path: "Model.swift"
    )
    let source = try file.source
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    state.synchronousClosureDepth = 1

    await #expect {
      try await evaluator.invoke(
        method: .slice, of: .sourceSlice(source),
        arguments: RuntimeArguments(
          values: [(nil, .integerRange(999..<1000))],
          location: location
        ),
        state: &state
      )
    } throws: { error in
      guard let error = error as? RuntimeError else { return false }
      return error.location == location && error.message
        .contains("a nonthrowing body cannot call a throwing API")
    }
  }
}
