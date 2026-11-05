import Benchmark
import BylawsSemantics

func registerSourceListCorrectionBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 20
  )
  for count in [10, 100] {
    let text = (0..<count).map {
      "let value\($0) = build(first: \($0), deprecated: false)"
    }.joined(separator: "\n")
    let expected = (0..<count).map {
      "let value\($0) = build(first: \($0), retry: true)"
    }.joined(separator: "\n")
    let file = try! FileCollector.collect(
      source: text, path: "/virtual/Arguments.swift"
    )
    let lists = try! file.calls.map { try $0.argumentList }
    precondition(lists.count == count)
    let edits = try! lists.flatMap { list in
      let correction = try SourceCorrection(combining: [
        list.removing(list[1]), list.inserting("retry: true"),
      ])
      return correction.fix?.edits ?? []
    }
    precondition(edits.count == count * 2)
    let source = try! file.source

    Benchmark(
      "Prepare \(count) argument list corrections",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        for list in lists {
          blackHole(try SourceCorrection(combining: [
            list.removing(list[1]), list.inserting("retry: true"),
          ]))
        }
      }
    }
    Benchmark(
      "Apply \(count) argument list corrections",
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
