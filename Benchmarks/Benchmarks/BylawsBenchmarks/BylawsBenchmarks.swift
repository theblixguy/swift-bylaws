import Benchmark
import BylawsCore
import BylawsSemantics
import Foundation

let benchmarks = { @Sendable in
  let smallSource = """
  import Foundation

  /// Presents data for the home screen.
  public final class HomeViewModel: BaseViewModel {
    @Published var title = "Home"

    func reload() {
      UserDefaults.standard.set(true, forKey: "seen")
    }
  }
  """

  let largeSource = (1...200).map { index in
    """
    final class Generated\(index): BaseViewModel {
      var value = \(index)

      func act\(index)() {
        UserDefaults.standard.set(\(index), forKey: "key\(index)")
      }
    }
    """
  }.joined(separator: "\n\n")

  let generatedSources = try! GeneratedSources()
  let generatedDirectoryTree = try! GeneratedDirectoryTree()

  Benchmark("Parse a small file") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(
        try FileCollector.collect(
          source: smallSource,
          path: "/virtual/Small.swift"
        )
      )
    }
  }

  Benchmark("Parse a large file") { benchmark in
    for _ in benchmark.scaledIterations {
      blackHole(
        try FileCollector.collect(
          source: largeSource,
          path: "/virtual/Large.swift"
        )
      )
    }
  }

  Benchmark("Glob matching") { benchmark in
    let globs: [Glob] = ["Sources/**", "**/Generated/**", "*ViewModel*.swift"]
    let paths = (1...100).map { "Sources/Feature\($0)/File\($0).swift" }
    for _ in benchmark.scaledIterations {
      for glob in globs {
        for path in paths {
          blackHole(glob.matches(path))
        }
      }
    }
  }

  if let path = ProcessInfo.processInfo.environment["BYLAWS_BENCHMARK_CLI"] {
    let executable = URL(fileURLWithPath: path)
    let files = try! CLIParseBenchmark(
      executable: executable, root: generatedSources.root,
      including: "Sources/**"
    )
    let directories = try! CLIParseBenchmark(
      executable: executable, root: generatedDirectoryTree.root,
      including: "Sources/Included/**"
    )
    Benchmark(
      "CLI checks 100 files",
      configuration: .init(
        metrics: [.wallClock],
        maxDuration: .seconds(10),
        maxIterations: 200
      )
    ) { _ in
      try withExtendedLifetime(generatedSources) { try files.run() }
    }
    Benchmark(
      "CLI skips 1,000 unrelated directories",
      configuration: .init(
        metrics: [.wallClock],
        maxDuration: .seconds(10),
        maxIterations: 200
      )
    ) { _ in
      try withExtendedLifetime(generatedDirectoryTree) { try directories.run() }
    }
  }

  Benchmark("Ten retained class queries") { benchmark in
    let cachedCodebase = Codebase(root: .directory(generatedSources.root.path))
    for _ in benchmark.scaledIterations {
      var selections: [Selection<Class>] = []
      for _ in 0..<10 {
        selections.append(try await cachedCodebase.classes)
      }
      blackHole(selections)
    }
  }

  Benchmark("Traverse 1,000 selected classes") { benchmark in
    let cachedCodebase = Codebase(root: .directory(generatedSources.root.path))
    let classes = try await cachedCodebase.classes
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      var nameBytes = 0
      for declaration in classes {
        nameBytes += declaration.name.utf8.count
      }
      blackHole(nameBytes)
    }
  }

  Benchmark("Traverse 1,000 nominal member views") { benchmark in
    let cachedCodebase = Codebase(root: .directory(generatedSources.root.path))
    let classes = try await cachedCodebase.classes
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      var nameBytes = 0
      for declaration in classes {
        for property in declaration.properties {
          nameBytes += property.name.utf8.count
        }
      }
      blackHole(nameBytes)
    }
  }

  Benchmark("Filter and match 1,000 classes") { benchmark in
    let cachedCodebase = Codebase(root: .directory(generatedSources.root.path))
    let classes = try await cachedCodebase.classes
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      blackHole(
        classes.suffixed("_1").where(.inherits(from: "BaseViewModel"))
      )
    }
  }
}
