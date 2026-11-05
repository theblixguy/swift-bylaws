import Benchmark
import BylawsSemantics

func registerStructuralCorrectionBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 20
  )
  for count in [10, 100] {
    let text = (0..<count).map {
      "func update\($0)() { if ready {} else { if available {} } }"
    }.joined(separator: "\n")
    let expected = (0..<count).map {
      "func update\($0)() { if ready {} else if available {} }"
    }.joined(separator: "\n")
    let file = try! FileCollector.collect(
      source: text,
      path: "/virtual/Branches.swift"
    )
    let branches = file.syntaxNodes(of: .ifExpression)
      .compactMap(\.ifExpression)
      .compactMap(\.elseBody)
    precondition(branches.count == count)
    let edits = try! branches.flatMap {
      try Unwrap($0, containingOnly: .ifExpression).correction.fix?.edits ?? []
    }
    precondition(edits.count == count)
    let source = try! file.source

    Benchmark(
      "Prepare \(count) else-if corrections",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        for branch in branches {
          blackHole(try Unwrap(branch, containingOnly: .ifExpression))
        }
      }
    }
    Benchmark(
      "Apply \(count) else-if corrections",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        let corrected = try source.replacement(applying: edits)
        precondition(corrected.replacement == expected)
        blackHole(corrected)
      }
    }
  }
}
