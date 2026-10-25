import Benchmark
import BylawsSemantics

func registerCorrectionBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 50
  )
  for count in [10, 100, 1000] {
    let text = (0..<count).map { "let value\($0) = 0xff" }
      .joined(separator: "\n") + "\n"
    let file = try! FileCollector.collect(
      source: text,
      path: "/virtual/Values.swift"
    )
    let source = try! file.source
    let edits = source.matches(of: /0xff/).map {
      $0.replacement(with: "0xFF")
    }
    precondition(edits.count == count)

    Benchmark(
      "Hash \(count) source corrections",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        let unique = Set(edits)
        precondition(unique.count == count)
        blackHole(unique)
      }
    }
    Benchmark(
      "Apply \(count) source corrections",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        let corrected = try source.replacement(applying: edits)
        precondition(!corrected.replacement.contains("0xff"))
        blackHole(corrected)
      }
    }
    let arithmetic = (0..<count).map { "let value\($0) = 1+2" }
      .joined(separator: "\n")
    let arithmeticFile = try! FileCollector.collect(
      source: arithmetic, path: "/virtual/Arithmetic.swift"
    )
    let operators = try! arithmeticFile.tokens.filter { $0.text == "+" }
    precondition(operators.count == count)
    Benchmark(
      "Space \(count) binary operators", configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        for token in operators {
          let spacing = try token.spacing
          blackHole(try spacing.before.replacement(with: .space))
          blackHole(try spacing.after.replacement(with: .space))
        }
      }
    }
    let callText = "send(" + (0..<count).map { "value\($0): \($0)" }
      .joined(separator: ", ") + ")"
    let callFile = try! FileCollector.collect(
      source: "func run() { \(callText) }", path: "/virtual/Call.swift"
    )
    let call = callFile.calls[0]
    precondition(call.arguments.count == count)
    Benchmark(
      "Render line with \(count) arguments",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(try call.arguments.replacement {
          Line { call.arguments }
        })
      }
    }
  }
}
