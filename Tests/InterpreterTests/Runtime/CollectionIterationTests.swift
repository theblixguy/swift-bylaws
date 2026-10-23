import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsInterpreter

@Suite("Portable collection iteration")
struct CollectionIterationTests {
  @Test(
    "Collection slices retain order and stop at first rejected element",
    arguments: [
      "[1, 2, 3].dropFirst() == [2, 3]",
      "[1, 2, 3].dropFirst(0) == [1, 2, 3]",
      "[1, 2, 3].dropFirst(20).isEmpty",
      "[1, 2, 3].dropFirst().startIndex == 1",
      "[1, 2, 3].dropFirst().endIndex == 3",
      "[1, 2, 3].dropFirst().indices.lowerBound == 1",
      "[1, 2, 3].dropFirst()[1] == 2",
      "[1, 2, 3].dropFirst().dropFirst()[2] == 3",
      "[1, 2, 3].dropFirst().prefix { $0 < 3 }.startIndex == 1",
      "[1, 2, 3].dropFirst().prefix { $0 < 3 }.endIndex == 2",
      "[1, 2, 3].dropFirst().prefix { $0 < 0 }.startIndex == 1",
      "[1, 2, 3].dropFirst(20).startIndex == 3",
      "[2, 3] == [1, 2, 3].dropFirst()",
      "[1, 2, 3].prefix(0).isEmpty",
      "[1, 2, 3].prefix(2) == [1, 2]",
      "[1, 2, 3].prefix(20) == [1, 2, 3]",
      "[1, 2, 3].dropFirst().prefix(0).startIndex == 1",
      "[1, 2, 3].dropFirst().prefix(0).endIndex == 1",
      "[1, 2, 3].dropFirst().prefix(1).startIndex == 1",
      "[1, 2, 3].dropFirst().prefix(1).endIndex == 2",
      "[1, 2, 3].dropFirst().prefix(1)[1] == 2",
      "[1, 2, 3].dropFirst().prefix(20).endIndex == 3",
      "[1, 2, 3].dropFirst(20).prefix(2).startIndex == 3",
      "[1, 3, 2].prefix { $0 < 3 } == [1]",
      "[1, 2, 3].prefix(while: { $0 < 3 }) == [1, 2]",
      "[1, 2, 3].prefix { $0 < 0 }.isEmpty",
      "[1, 2, 3].prefix { $0 < 10 } == [1, 2, 3]",
      "[4, 5, 6][1] == 5",
      "[4, 5, 6].indices.count == 3",
      "[4, 5, 6].startIndex == 0 && [4, 5, 6].endIndex == 3",
      "[4, 5, 6][[4, 5, 6].endIndex - 1] == 6",
    ]
  )
  func slices(expression: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("slices") {
        try await app.classes.violations(of: Matcher<Class>("preserve collection order") { _ in
          \(expression)
        })
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Sequence consumers read integer ranges",
    arguments: [
      "Set([0, 1]).isSubset(of: (0..<3))",
      "!Set([3]).isSubset(of: (0..<3))",
      "Set([0, 1]).isSubset(of: [4, 5].indices)",
      "[1, 2].flatMap { 0..<$0 } == [0, 0, 1]",
      "[1, 2].flatMap { _ in [4, 5].indices } == [0, 1, 0, 1]",
      "[1, 2].flatMap { _ in 0..<0 }.isEmpty",
      "Dictionary(grouping: (0..<3), by: { $0 }).count == 3",
      "Dictionary(grouping: [4, 5].indices, by: { $0 }).count == 2",
    ]
  )
  func rangeConsumers(expression: String) async throws {
    let project = try correctionProject(ruleBody: """
    try await app.classes.violations(of: Matcher<Class>("read integer ranges") { _ in
      \(expression)
    })
    """)
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Range consumers stop at evaluation budget without materialisation",
    arguments: [SupportedAPI.Method.isSubset, .flatMap]
  )
  func rangeConsumerBudget(method: SupportedAPI.Method) async throws {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .init(
      maximumInstructions: 10, maximumCallDepth: 10
    ))
    let values: [RuntimeValue] = method == .isSubset
      ? [.integer(Int.max)] : [.integerRange(0..<Int.max)]
    let arguments = RuntimeArguments(
      values: method == .isSubset
        ? [("of", .integerRange(0..<Int.max))]
        : [(nil, .keyPath([], location))],
      location: location
    )

    await #expect {
      try await evaluator.collectionMethod(
        method, values: values[...], preservesSet: method == .isSubset,
        arguments: arguments, state: &state
      )
    } throws: { error in
      (error as? RuntimeError)?.message == "the rule exceeded its evaluation budget"
    }
  }

  @Test("Range grouping stops at evaluation budget without materialisation")
  func rangeGroupingBudget() async throws {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .init(
      maximumInstructions: 10, maximumCallDepth: 10
    ))
    let arguments = RuntimeArguments(values: [
      ("grouping", .integerRange(0..<Int.max)),
      ("by", .keyPath([], location)),
    ], location: location)

    await #expect {
      try await evaluator.groupDictionary(arguments: arguments, state: &state)
    } throws: { error in
      (error as? RuntimeError)?.message == "the rule exceeded its evaluation budget"
    }
  }

  @Test(
    "Slice element coercion retains helper values and indices",
    arguments: [0, 1, 2, 3]
  )
  func sliceCoercion(droppedCount: Int) async throws {
    let project = try correctionProject(
      declarations: """
      func optionals(_ values: ArraySlice<Int?>) -> ArraySlice<Int?> { values }
      """,
      ruleBody: """
      let input = [1, 2, 3].dropFirst(\(droppedCount))
      let output = optionals(input)
      try await app.classes.violations(of: Matcher<Class>("retain coerced slice indices") { _ in
        output.startIndex == \(droppedCount) && output.endIndex == 3
          && output.indices == input.indices
          && output.allSatisfy { $0 != nil }
          && output.map { $0 ?? 0 } == input.map { $0 }
      })
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test("Slice element coercion rejects incompatible values without mutation")
  func rejectedSliceCoercion() {
    let input: [RuntimeValue] = [.boolean(false), .integer(2), .string("text")]
    let slice = input.dropFirst()
    let result = RuntimeValue.arraySlice(slice)
      .coerced(to: .arraySlice(.optional(.integer)))

    #expect(result == nil)
    #expect(slice.startIndex == 1)
    #expect(slice.endIndex == 3)
    #expect(slice[1].hasRuntimeType(.integer))
    #expect(slice[2].hasRuntimeType(.string))
  }

  @Test("Selection indices support source-order iteration and subscripts")
  func selectionIndices() async throws {
    let project = try rulesProject(
      rules: """
      Rule("indices") {
        let values = try await app.classes
        for index in values.indices {
          if index > values.startIndex {
            Violations(rule: "test iteration", offenders: [values[index]], checkedCount: 1)
          }
        }
      }
      """,
      sources: [
        "Sources/Models.swift": "class Alpha {}\nclass Beta {}\nclass Gamma {}",
      ]
    )

    let names = try await offenderNames(ofFirstRuleIn: project)

    #expect(names == ["Beta", "Gamma"])
  }

  @Test(
    "Collection operations reject negative counts and out-of-bounds indices",
    arguments: [
      "[1, 2].dropFirst(-1)",
      "[1, 2].prefix(-1)",
      "values.prefix(-1)",
      "[1, 2][-1]",
      "[1, 2][2]",
      "[1, 2].dropFirst()[0]",
      "values[values.endIndex]",
    ]
  )
  func rejectedBounds(expression: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("bounds") {
        let values = try await app.classes
        let result = \(expression)
        values.violations(of: .isFinal)
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = try await loadedProgram(in: project)
    let rule = try #require(program.rules.first)

    await #expect(throws: RuleError.self) {
      try await rule.violations()
    }
  }

  @Test("Collection subscript checks index type during loading")
  func indexType() async throws {
    let project = try rulesProject(
      rules: """
      Rule("index-type") {
        let names = ["Alpha", "Beta"]
        let name = names["first"]
        try await app.classes.violations(of: .isFinal)
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(program.errors.contains {
      $0.message == "the collection index must be Int, not String"
    })
    #expect(program.rules.isEmpty)
  }

  @Test("Selection slices retain original indices")
  func selectionSlice() async throws {
    let project = try rulesProject(
      rules: """
      Rule("slice") {
        let values = try await app.classes
        let remaining = values.dropFirst()
        values.violations(of: Matcher<Class>("preserve selection indices") { _ in
          remaining.startIndex == 1 && remaining[1].name == "Beta"
            && values.prefix(1).count == 1
            && values.prefix(1)[0].name == "Alpha"
            && remaining.prefix(1).startIndex == 1
            && remaining.prefix(1).endIndex == 2
            && remaining.prefix(1)[1].name == "Beta"
        })
      }
      """,
      sources: ["Sources/Models.swift": "class Alpha {}\nclass Beta {}"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 2)
    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Prefix count checks argument type during loading",
    arguments: [
      ("\"two\"", "String"),
      ("true", "Bool"),
      ("2.5", "Double"),
    ]
  )
  func prefixCountType(expression: String, type: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("prefix-count-type") {
        let values = [1, 2, 3].prefix(\(expression))
        try await app.classes.violations(of: .isFinal)
      }
      """,
      sources: ["Sources/Model.swift": "class Model {}"]
    )
    let program = await RuleProgram.loaded(
      fromFiles: [project.fileURL(for: "ProjectRules.swift").path]
    )

    #expect(program.errors.contains {
      $0.message == "the prefix count must be Int, not \(type)"
    })
    #expect(program.rules.isEmpty)
  }

  @Test(
    "Prefix keeps stored and named predicate overloads",
    arguments: ["precedesThree", "predicate"]
  )
  func prefixPredicate(callable: String) async throws {
    let project = try correctionProject(
      declarations: """
      func precedesThree(_ value: Int) -> Bool { value < 3 }
      """,
      ruleBody: """
      let predicate = { (value: Int) in value < 3 }
      let values = [1, 2, 3].prefix(\(callable))
      try await app.classes.violations(of: Matcher<Class>("keep prefix predicate") { _ in
        values == [1, 2]
      })
      """
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.checkedCount == 1)
    #expect(findings.violations.isEmpty)
  }

  @Test(
    "Large range iteration stops at evaluation budget without materialisation"
  )
  func rangeBudget() async throws {
    let location = DeclarationLocation.start(of: "ProjectRules.swift")
    var environment = RuntimeEnvironment()
    environment.bind(.integerRange(0..<Int.max), to: "indices")
    let evaluator = RuntimeEvaluator(globals: environment)
    var state = RuntimeEvaluationState(limits: .init(
      maximumInstructions: 10, maximumCallDepth: 10
    ))
    let body = RuntimeBody(statements: [RuntimeStatement(
      kind: .forStatement(
        name: "index",
        sequence: RuntimeExpression(
          kind: .reference("indices"),
          location: location
        ),
        body: RuntimeBody(statements: [])
      ),
      location: location
    )])

    await #expect {
      try await evaluator.evaluate(body, in: environment, state: &state)
    } throws: { error in
      (error as? RuntimeError)?.message == "the rule exceeded its evaluation budget"
    }
  }
}
