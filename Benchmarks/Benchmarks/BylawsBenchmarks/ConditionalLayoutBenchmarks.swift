import Benchmark
import BylawsSemantics

func registerConditionalLayoutBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 20
  )
  for count in [10, 100, 1000] {
    let body = (0..<count).map { "  send(value: \($0), other: 1)" }
      .joined(separator: "\n")
    let text = "func run() {\n\(body)\n}\n"
    let file = try! FileCollector.collect(
      source: text,
      path: "/virtual/Calls.swift"
    )
    let source = try! file.source
    for syntaxQuery in [false, true] {
      let route = syntaxQuery ? "syntax" : "declaration"
      let calls = if syntaxQuery {
        file.syntaxNodes(of: .functionCall).compactMap(\.call)
      } else {
        file.calls
      }
      precondition(calls.count == count)
      for width in [20, 100] {
        Benchmark(
          "Capture \(route) \(count) layouts at width \(width)",
          configuration: configuration
        ) { benchmark in
          for _ in benchmark.scaledIterations {
            let edits = try calls.map { call in
              try call.arguments.replacement(whenLineExceeds: width) {
                for argument in call.arguments {
                  Newline()
                  argument
                }
                Newline()
              }
            }
            precondition(edits.count == count)
            blackHole(edits)
          }
        }
      }
      Benchmark(
        "Query and capture \(route) \(count) layouts",
        configuration: configuration
      ) { benchmark in
        for _ in benchmark.scaledIterations {
          let selected = if syntaxQuery {
            file.syntaxNodes(of: .functionCall).compactMap(\.call)
          } else {
            file.calls
          }
          let edits = try selected.map { call in
            try call.arguments.replacement(whenLineExceeds: 100) {
              for argument in call.arguments {
                Newline()
                argument
              }
              Newline()
            }
          }
          precondition(edits.count == count)
          blackHole(edits)
        }
      }
      let edits = try! calls.map { call in
        try call.arguments.replacement {
          for argument in call.arguments {
            Newline()
            argument
          }
          Newline()
        }
      }
      Benchmark(
        "Compose \(route) \(count) independent layouts",
        configuration: configuration
      ) { benchmark in
        for _ in benchmark.scaledIterations {
          blackHole(try source.replacement(applying: edits))
        }
      }
    }
  }

  for padding in [16384, 262_144, 1_048_576] {
    let text = "func run() { send(value: 1, other: 2) }\n"
      + String(repeating: "// padding\n", count: padding / 11)
    let file = try! FileCollector.collect(
      source: text,
      path: "/virtual/Padded.swift"
    )
    let call = file.calls[0]
    Benchmark(
      "Capture layout before \(padding) trailing bytes",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(try call.arguments.replacement(whenLineExceeds: 100) {
          for argument in call.arguments {
            Newline()
            argument
          }
          Newline()
        })
      }
    }
  }

  for depth in [4, 8, 16, 32] {
    var expression = "leaf(first: 1, second: 2)"
    for _ in 1..<depth { expression = "send(first: \(expression), second: 2)" }
    let file = try! FileCollector.collect(
      source: "func run() { \(expression) }", path: "/virtual/Nested.swift"
    )
    let source = try! file.source
    let calls = file.calls
    precondition(calls.count == depth)
    let edits = try! calls.map { call in
      try call.arguments.replacement {
        for argument in call.arguments {
          Newline()
          argument
        }
        Newline()
      }
    }
    Benchmark(
      "Compose \(depth) nested layouts",
      configuration: configuration
    ) { benchmark in
      for _ in benchmark.scaledIterations {
        blackHole(try source.replacement(applying: edits))
      }
    }
  }
}
