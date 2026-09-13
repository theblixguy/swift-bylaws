import BylawsSemantics
import Testing

@Suite("Cyclomatic complexity collection")
struct CyclomaticComplexityTests {
  @Test(
    "An async for loop, if expression, switch expression, guard and catch add complexity"
  )
  func countsModernControlFlow() throws {
    let file = try FileCollector.collect(
      source: """
      func classify<S: AsyncSequence>(_ values: S) async throws -> String
        where S.Element == Int
      {
        for try await value in values {
          let sign = if value > 0 { 1 } else { -1 }
          let label = switch sign {
          case 1: "positive"
          case -1: "negative"
          default: "zero"
          }
          guard case .some = Optional(label) else { continue }
          do {
            try consume(label)
          } catch {
            return "failed"
          }
        }
        return "done"
      }
      """,
      path: "/virtual/App/Modern.swift"
    )

    let classify = try #require(file.functions.first)
    #expect(classify.cyclomaticComplexity == 7)
  }

  @Test("Fallthrough joins two switch cases")
  func subtractsFallthrough() throws {
    let file = try FileCollector.collect(
      source: """
      func describe(_ value: Int) {
        switch value {
        case 0:
          fallthrough
        case 1:
          print("small")
        default:
          print("other")
        }
      }
      """,
      path: "/virtual/App/Switch.swift"
    )

    let describe = try #require(file.functions.first)
    #expect(describe.cyclomaticComplexity == 2)
  }

  @Test("While and repeat loops each add one complexity point")
  func countsRemainingLoopForms() throws {
    let file = try FileCollector.collect(
      source: """
      func drain() {
        while hasNext { takeNext() }
        repeat { retry() } while shouldRetry
      }
      """,
      path: "/virtual/App/Loops.swift"
    )

    let drain = try #require(file.functions.first)
    #expect(drain.cyclomaticComplexity == 2)
  }

  @Test(
    "Control flow in a closure counts in the parent function, but control flow in a local function does not"
  )
  func respectsLexicalRegions() throws {
    let file = try FileCollector.collect(
      source: """
      func outer() {
        if enabled { work() }
        let callback = {
          if ready { finish() }
        }
        func nested() {
          if first { work() }
          guard second else { return }
        }
        callback()
      }
      """,
      path: "/virtual/App/Nested.swift"
    )

    let outer = try #require(file.functions.first)
    #expect(outer.cyclomaticComplexity == 2)
  }

  @Test("Complexity includes initialisers and all compilation branches")
  func countsInitializerControlFlow() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
        init() async throws(StoreError) {
      #if FEATURE
          if enabled { await prepare() }
      #else
          guard ready else { throw .notReady }
      #endif
        }
      }
      """,
      path: "/virtual/App/Store.swift"
    )

    let initializer = try #require(file.initializers.first)
    #expect(initializer.cyclomaticComplexity == 2)
    #expect(initializer.awaitCount == 1)
  }

  @Test("Async, await and typed throws add no complexity")
  func ignoresNonBranchingLanguageFeatures() throws {
    let file = try FileCollector.collect(
      source: """
      actor Worker {
        func run() async throws(WorkError) {
          await perform()
          #trace("running")
        }
      }
      """,
      path: "/virtual/App/Worker.swift"
    )

    let run = try #require(file.functions.first)
    #expect(run.cyclomaticComplexity == 0)
    #expect(run.awaitCount == 1)
  }

  @Test("A declaration without a body has zero complexity")
  func protocolRequirement() throws {
    let file = try FileCollector.collect(
      source: """
      protocol Worker {
        func run() async throws(WorkError)
      }
      """,
      path: "/virtual/App/Worker.swift"
    )

    let run = try #require(file.protocols.first?.requiredFunctions.first)
    #expect(run.cyclomaticComplexity == 0)
  }
}
