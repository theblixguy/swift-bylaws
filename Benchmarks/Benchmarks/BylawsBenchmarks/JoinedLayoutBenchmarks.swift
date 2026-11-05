import Benchmark
import BylawsCore
import BylawsSemantics

func registerJoinedLayoutBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 20
  )
  for count in [10, 100] {
    let text = (0..<count).map {
      "let value\($0) = send(.info, \"Ready\", values: [1, 2])"
    }.joined(separator: "\n")
    let expected = (0..<count).map {
      """
      let value\($0) = send(
        .info, "Ready",
        values: [
          1,
          2
        ]
      )
      """
    }.joined(separator: "\n")
    let file = try! FileCollector.collect(
      source: text, path: "/virtual/Joined.swift"
    )
    let calls = file.calls
    precondition(calls.count == count)
    let source = try! file.source

    func corrections() throws -> SourceCorrection {
      try SourceCorrection(combining: calls.map { call in
        let arguments = call.arguments
        let leading = arguments.prefix { $0.label == nil }
        let remaining = arguments.dropFirst(leading.count)
        let collections = remaining.compactMap { $0.expression?.elements }
        return try Layout(arguments) {
          Lines(boundaries: .newline) {
            Joined(leading)
            remaining
          }
        }.applying(toEach: collections) {
          Lines($0, boundaries: .newline)
        }.correction
      })
    }

    let fix = try! corrections().fix!
    precondition(fix.edits.count == count)
    precondition(try! source.replacement(applying: fix.edits)
      .replacement == expected)
    Benchmark(
      "Prepare \(count) joined layouts with child lists",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(try corrections())
      }
    }
    Benchmark(
      "Apply \(count) joined layouts with child lists",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        let corrected = try source.replacement(applying: fix.edits)
        precondition(corrected.replacement == expected)
        blackHole(corrected)
      }
    }
  }
}
