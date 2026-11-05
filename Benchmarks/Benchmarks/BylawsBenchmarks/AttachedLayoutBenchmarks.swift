import Benchmark
import BylawsCore
import BylawsSemantics

func registerAttachedLayoutBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 20
  )
  for count in [10, 100] {
    let text = (0..<count).map {
      "let value\($0) = send(first: \($0), values: [1, 2])"
    }.joined(separator: "\n")
    let expanded = (0..<count).map {
      """
      let value\($0) = send(
        first: \($0),
        values: [
          1,
          2
        ]
      )
      """
    }.joined(separator: "\n")
    let file = try! FileCollector.collect(
      source: text, path: "/virtual/Collections.swift"
    )
    let calls = file.calls
    precondition(calls.count == count)
    let source = try! file.source

    for minimumLength in [1, 1000] {
      let condition = SourceLayoutCondition.maximumLineLength(minimumLength...)
      let state = minimumLength == 1 ? "active" : "inactive"
      let expected = minimumLength == 1 ? expanded : text

      func corrections() throws -> SourceCorrection {
        try SourceCorrection(combining: calls.map { call in
          try Layout(call.arguments, when: condition) {
            Lines(call.arguments, boundaries: .newline)
          }.applying {
            for elements in call.arguments
              .compactMap({ $0.expression?.elements })
            {
              try Layout(
                elements,
                layout: Lines(elements, boundaries: .newline)
              )
            }
          }.correction
        })
      }

      let fix = try! corrections().fix!
      precondition(fix.edits.count == (minimumLength == 1 ? count : 0))

      Benchmark(
        "Prepare \(count) \(state) layouts with contained corrections",
        configuration: configuration
      ) { benchmark in
        for _ in benchmark.scaledIterations {
          blackHole(try corrections())
        }
      }
      guard minimumLength == 1 else { continue }
      Benchmark(
        "Apply \(count) \(state) layouts with contained corrections",
        configuration: configuration
      ) { benchmark in
        for _ in benchmark.scaledIterations {
          let corrected = try source.replacement(
            applying: fix.edits
          )
          precondition(corrected.replacement == expected)
          blackHole(corrected)
        }
      }
    }
  }
}
