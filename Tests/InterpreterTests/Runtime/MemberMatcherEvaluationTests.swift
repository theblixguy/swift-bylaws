import BylawsCore
import BylawsSemantics
import Testing
@testable import BylawsInterpreter

@Suite("Member matcher evaluation")
struct MemberMatcherEvaluationTests {
  @Test("Reporting a failure does not evaluate the member predicate again")
  func evaluatesOnce() async throws {
    let app =
      Codebase(
        root: .sources(["Model.swift": "class Model { func load() {} }"])
      )
    let model = RuntimeModelValue
      .classDeclaration(try #require(await app.classes.first))
    let location = DeclarationLocation.start(of: "Rules.swift")
    let closure = RuntimeClosure(definition: RuntimeClosureDefinition(
      parameters: [], body: RuntimeBody(statements: [RuntimeStatement(
        kind: .expression(RuntimeExpression(
          kind: .boolean(false),
          location: location
        )), location: location
      )]), location: location, usesAwait: false, usesTry: false
    ), captures: RuntimeEnvironment())
    let member = RuntimeMatcher(
      subjectType: .function,
      requirement: "pass",
      predicate: .closure(closure)
    )
    let matcher = RuntimeMatcher(
      subjectType: .classDeclaration,
      requirement: "have passing functions",
      predicate: .members(
        all: true,
        path: [.functions],
        matcher: member,
        location: location
      )
    )
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var matchState = RuntimeEvaluationState(limits: .standard)
    var reportState = RuntimeEvaluationState(limits: .standard)

    _ = try await evaluator.matches(matcher, value: model, state: &matchState)
    _ = try await evaluator.selectionMethod(
      .violations,
      selection: RuntimeSelection(
        family: .class, elements: [model], queryDescription: "classes",
        rootPath: nil
      ),
      arguments: RuntimeArguments(
        values: [("of", .matcher(matcher))],
        location: location
      ),
      state: &reportState
    )

    #expect(reportState.remainingInstructions == matchState
      .remainingInstructions)
  }
}
