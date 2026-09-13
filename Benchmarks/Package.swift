// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .treatAllWarnings(as: .error),
  .strictMemorySafety(),
  .defaultIsolation(nil),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
  name: "benchmarks",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "..", traits: []),
    .package(url: "https://github.com/ordo-one/benchmark", from: "1.4.0"),
  ],
  targets: [
    .executableTarget(
      name: "BylawsBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "benchmark"),
        .product(name: "BylawsCore", package: "swift-bylaws"),
        .product(name: "BylawsSemantics", package: "swift-bylaws"),
      ],
      path: "Benchmarks/BylawsBenchmarks",
      swiftSettings: swiftSettings,
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark"),
      ]
    ),
  ]
)
