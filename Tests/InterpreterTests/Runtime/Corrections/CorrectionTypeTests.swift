import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

@Suite("Correction types")
struct CorrectionTypeTests {
  @Test("Inline fix annotations match contextual signature", arguments: [
    (
      "(context: FixContext<Function>)", "[SourceFix.Edit]", "return []",
      "the closure parameter must be FixContext<Function>"
    ),
    (
      "(context: FixContext<Class>)", "String", "return \"wrong\"",
      "the closure must be [SourceFix.Edit]"
    ),
    ("()", "[SourceFix.Edit]", "return []", "the closure takes 0 arguments"),
    (
      "(first: FixContext<Class>, second: FixContext<Class>)",
      "[SourceFix.Edit]", "return []", "the closure takes 2 arguments"
    ),
    (
      "(context: Missing)", "[SourceFix.Edit]", "return []",
      "portable rules do not support the 'Missing' type"
    ),
  ])
  func inlineSignature(
    parameters: String, result: String, body: String, expected: String
  ) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal)
      .withFix { \(parameters) -> \(result) in \(body) }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: expected,
      atLine: 6
    )
  }

  @Test("Named fix helpers match contextual signature", arguments: [
    (
      "_ context: FixContext<Function>", "[SourceFix.Edit]", "return []",
      "the fix context must be FixContext<Function>"
    ),
    (
      "",
      "[SourceFix.Edit]",
      "return []",
      "the fix function takes one FixContext"
    ),
    (
      "_ first: FixContext<Class>, _ second: FixContext<Class>",
      "[SourceFix.Edit]", "return []", "the fix function takes one FixContext"
    ),
    (
      "_ context: FixContext<Class>", "String", "return \"wrong\"",
      "the fix result must be [SourceFix.Edit]"
    ),
  ])
  func namedSignature(
    parameters: String, result: String, body: String, expected: String
  ) async throws {
    let project = try correctionProject(
      declarations: "func rename(\(parameters)) -> \(result) { \(body) }",
      ruleBody: "try await app.classes.violations(of: .isFinal).withFix(rename)"
    )

    await expectCorrectionRejection(
      in: project,
      containing: expected,
      atLine: 5
    )
  }

  @Test("Fix builder rejects non-edit value")
  func fixResult() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal)
      .withFix { context in 42 }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "withFix takes SourceFix, SourceFix.Edit or edit arrays",
      atLine: 6
    )
  }

  @Test(
    "Matching inline and stored fix annotations retain exact edit",
    arguments: [false, true]
  )
  func matchingAnnotations(stored: Bool) async throws {
    let closure = """
    { (context: FixContext<Class>) -> [SourceFix.Edit] in
      return [try context.offender.nameSource.replacement(with: "Updated")]
    }
    """
    let project = try correctionProject(
      declarations: stored ? "let rename = \(closure)" : "",
      ruleBody: "try await app.classes.violations(of: .isFinal).withFix(\(stored ? "rename" : closure))"
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.compactMap(\.self).first)

    #expect(fix.edits.count == 1)
    let edit = try #require(fix.edits.first)
    #expect(edit.source.text == "Model")
    #expect(edit.source.range == 6..<11)
    #expect(edit.replacement == "Updated")
  }

  @Test(
    "Written result rejects incompatible or missing conditional value",
    arguments: [
      ("if flag { \"ok\" } else { 42 }", "Int"),
      ("if flag { \"ok\" }", "Void"),
      ("if flag { if flag { \"ok\" } else { 42 } } else { \"ok\" }", "Int"),
    ]
  )
  func conditionalResult(body: String, rejectedType: String) async throws {
    let project = try correctionProject(
      declarations: "let choose = { (flag: Bool) -> String in \(body) }",
      ruleBody: "try await app.classes.violations(of: .isFinal)"
    )

    await expectCorrectionRejection(
      in: project,
      containing: "the closure must be String, not \(rejectedType)",
      atLine: 3
    )
  }

  @Test("Same-type conditional results retain both branch values")
  func conditionalStringResults() async throws {
    let project = try correctionProject(
      declarations: """
      let choose = { (flag: Bool) -> String in
        if flag { "Model" } else { "Other" }
      }
      """,
      ruleBody: """
      if choose(true) == "Model" && choose(false) == "Other" {
        try await app.classes.violations(of: .isFinal)
      }
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.offenders.map(\.name) == ["Model"])
  }

  @Test("Optional conditional result retains value and nil branches")
  func conditionalOptionalResults() async throws {
    let project = try correctionProject(
      declarations: """
      let choose = { (flag: Bool) -> String? in
        if flag { "Model" } else { nil }
      }
      """,
      ruleBody: """
      if let name = choose(true) {
        try await app.classes.named(name).violations(of: .isFinal)
      }
      if let name = choose(false) {
        try await app.classes.named(name).violations(of: .isFinal)
      }
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.offenders.map(\.name) == ["Model"])
    #expect(findings.violations.checkedCount == 1)
  }

  @Test("Written optional closure result supports optional binding")
  func optionalResultBinding() async throws {
    let project = try correctionProject(
      declarations: "let maybe = { () -> String? in \"Model\" }",
      ruleBody: """
      if let name = maybe() {
        try await app.classes.named(name).violations(of: .isFinal)
      }
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.offenders.map(\.name) == ["Model"])
  }

  @Test("Written optional closure result must be unwrapped for condition")
  func optionalResultCondition() async throws {
    let project = try correctionProject(
      declarations: "let maybe = { () -> String? in \"Model\" }",
      ruleBody: """
      if maybe().contains("Model") {
        try await app.classes.violations(of: .isFinal)
      }
      """
    )

    await expectCorrectionRejection(
      in: project, containing: "the condition must be Bool, not Bool?",
      atLine: 5
    )
  }

  @Test("Matcher rejects optional result annotation")
  func matcherOptionalResult() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(matching: Matcher<Class>("match") {
      (value: Class) -> Bool? in true
    })
    """)

    await expectCorrectionRejection(
      in: project, containing: "the closure must be Bool, not Bool?",
      atLine: 5
    )
  }

  @Test("Fix builder rejects optional edit array annotation")
  func fixOptionalResult() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: .isFinal).withFix {
      (context: FixContext<Class>) -> [SourceFix.Edit]? in
      [try context.offender.nameSource.replacement(with: "Updated")]
    }
    """)

    await expectCorrectionRejection(
      in: project,
      containing: "the closure must be [SourceFix.Edit], not [SourceFix.Edit]?",
      atLine: 5
    )
  }

  @Test("Matching contextual result annotations retain exact fix")
  func contextualResults() async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(matching: Matcher<Class>("match") {
      (value: Class) -> Bool in value.name == "Model"
    }).withFix { (context: FixContext<Class>) -> [SourceFix.Edit] in
      [try context.offender.nameSource.replacement(with: "Updated")]
    }
    """)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.compactMap(\.self).first)
    let edit = try #require(fix.edits.first)

    #expect(findings.violations.offenders.map(\.name) == ["Model"])
    #expect(fix.edits.count == 1)
    #expect(edit.source.text == "Model")
    #expect(edit.source.range == 6..<11)
    #expect(edit.replacement == "Updated")
  }

  @Test(
    "Collection rejects stored closure arity and input mismatches",
    arguments: [
      (
        "{ () -> String in \"unused\" }",
        "the collection closure takes one parameter"
      ),
      (
        "{ (value: Function) -> String in value.name }",
        "the collection element must be Function"
      ),
    ]
  )
  func storedCollectionSignature(
    closure: String,
    expected: String
  ) async throws {
    let project = try correctionProject(
      declarations: "let read = \(closure)",
      ruleBody: """
      let values = try await app.properties
      let texts = values.map(read)
      try await app.classes.violations(of: .isFinal)
      """
    )

    await expectCorrectionRejection(
      in: project,
      containing: expected,
      atLine: 6
    )
  }
}
