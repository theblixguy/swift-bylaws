import Benchmark
import BylawsSemantics

func registerSourceLoadingBenchmarks() {
  let configuration = Benchmark.Configuration(
    metrics: [.wallClock, .mallocCountTotal, .mallocBytesCount],
    maxDuration: .seconds(3), maxIterations: 50
  )
  let text = (0..<1000).map { "let value\($0) = \($0)" }
    .joined(separator: "\n") + "\n"
  let file = try! FileCollector.collect(
    source: text, path: "/virtual/Values.swift"
  )
  precondition(file.properties.count == 1000)
  precondition(try! file.properties[0].source.text == "value0 = 0")
  precondition(try! file.properties[0].nameSource.text == "value0")
  precondition(try! file.properties[999].nameSource.text == "value999")

  Benchmark(
    "Collect 1,000 properties", configuration: configuration
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      let file = try FileCollector.collect(
        source: text, path: "/virtual/Values.swift"
      )
      blackHole(file)
    }
  }
  Benchmark(
    "Collect 1,000 properties and read first source",
    configuration: configuration
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      let file = try FileCollector.collect(
        source: text, path: "/virtual/Values.swift"
      )
      blackHole(file)
      blackHole(try file.properties[0].source)
    }
  }
  Benchmark(
    "Collect 1,000 properties and read first name",
    configuration: configuration
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      let file = try FileCollector.collect(
        source: text, path: "/virtual/Values.swift"
      )
      blackHole(file)
      blackHole(try file.properties[0].nameSource)
    }
  }
  Benchmark(
    "Collect 1,000 properties and read all names",
    configuration: configuration
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      let file = try FileCollector.collect(
        source: text, path: "/virtual/Values.swift"
      )
      for property in file.properties {
        blackHole(try property.nameSource)
      }
    }
  }
}
