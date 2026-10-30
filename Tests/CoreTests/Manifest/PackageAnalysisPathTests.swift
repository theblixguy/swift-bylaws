import BylawsSemantics
import Testing
@testable import BylawsCore

@Suite("Package target source paths", .tags(.layering))
struct PackageAnalysisPathTests {
  @Test("Target directories match complete path components")
  func directoryBoundaries() throws {
    let paths = [
      "/project/Sources/AppExtra/Other.swift",
      "/project/Sources/App/Second.swift",
      "/project/Sources/App/First.swift",
    ]
    let analysis = try makeAnalysis(
      targets: """
      .target(name: "App"),
      .target(name: "Parent", path: "Sources"),
      """,
      paths: paths
    )
    let app = try #require(analysis.targets.first { $0.name == "App" })
    let parent = try #require(analysis.targets.first { $0.name == "Parent" })

    #expect(analysis.files(of: app).map(\.path) == Array(paths.dropFirst()))
    #expect(analysis.files(of: parent).map(\.path) == paths)
  }

  @Test("Target and selection aliases keep source order and exclusions")
  func normalisedSelections() throws {
    let selected = "/project/Sources/App/Included/../Included/One.swift"
    let analysis = try makeAnalysis(
      targets: """
      .target(
        name: "App", path: "Sources/Ignored/../App/.",
        exclude: ["./Included/../Included/Excluded.swift"],
        sources: ["./Included/../Included"]
      )
      """,
      paths: [
        "/project/Sources/App/IncludedExtra/Other.swift",
        "/project/Sources/App/Included/Excluded.swift",
        selected,
      ]
    )
    let target = try #require(analysis.targets.first)

    #expect(analysis.files(of: target).map(\.path) == [selected])
  }

  @Test(
    "Explicit source selections preserve empty and component semantics",
    arguments: [
      ("[]", [String]()),
      (
        "[\"\"]",
        [
          "Included/One.swift",
          "Included/One.swift.more/Other.swift",
          "IncludedExtra/Other.swift",
        ]
      ),
      (
        "[\".\"]",
        [
          "Included/One.swift",
          "Included/One.swift.more/Other.swift",
          "IncludedExtra/Other.swift",
        ]
      ),
      (
        "[\"Included\"]",
        ["Included/One.swift", "Included/One.swift.more/Other.swift"]
      ),
      ("[\"Included/One.swift\"]", ["Included/One.swift"]),
      ("[\"/\"]", []),
    ]
  )
  func explicitSelections(sources: String, expected: [String]) throws {
    let prefix = "/project/Sources/App/"
    let analysis = try makeAnalysis(
      targets: ".target(name: \"App\", sources: \(sources))",
      paths: [
        prefix + "Included/One.swift",
        prefix + "Included/One.swift.more/Other.swift",
        prefix + "IncludedExtra/Other.swift",
      ]
    )
    let target = try #require(analysis.targets.first)

    #expect(analysis.files(of: target).map(\.path) == expected
      .map { prefix + $0 })
  }

  @Test("Excluded directories match complete path components")
  func excludedDirectories() throws {
    let selected = "/project/Sources/App/IncludedExtra/One.swift"
    let analysis = try makeAnalysis(
      targets: ".target(name: \"App\", exclude: [\"Included\"])",
      paths: ["/project/Sources/App/Included/Other.swift", selected]
    )
    let target = try #require(analysis.targets.first)

    #expect(analysis.files(of: target).map(\.path) == [selected])
  }

  @Test("Root target keeps relative source selections")
  func rootDirectory() throws {
    let analysis = try makeAnalysis(
      targets: ".target(name: \"App\", path: \".\", sources: [\"One.swift\"])",
      paths: ["/One.swift", "/Other.swift"],
      rootPath: "/"
    )
    let target = try #require(analysis.targets.first)

    #expect(analysis.files(of: target).map(\.path) == ["/One.swift"])
  }

  @Test("Unicode path spellings retain byte identity")
  func unicodePaths() throws {
    let composed = "\u{00E9}"
    let decomposed = "e\u{0301}"
    let first = "/project/Sources/\(composed)/One.swift"
    let second = "/project/Sources/\(decomposed)/Two.swift"
    let analysis = try makeAnalysis(
      targets: """
      .target(name: "Composed", path: "Sources/\(composed)"),
      .target(name: "Decomposed", path: "Sources/\(decomposed)"),
      .target(
        name: "Selected", path: "Sources",
        exclude: ["\(decomposed)"], sources: ["\(composed)"]
      ),
      """,
      paths: [first, second]
    )
    let composedTarget = try #require(analysis.targets
      .first { $0.name == "Composed" })
    let decomposedTarget = try #require(analysis.targets
      .first { $0.name == "Decomposed" })
    let selected = try #require(analysis.targets
      .first { $0.name == "Selected" })

    #expect(analysis.files(of: composedTarget).map(\.path) == [first])
    #expect(analysis.files(of: decomposedTarget).map(\.path) == [second])
    #expect(analysis.files(of: selected).map(\.path) == [first])
  }

  private func makeAnalysis(
    targets: String,
    paths: [String],
    rootPath: String = "/project"
  ) throws -> PackageAnalysis {
    let files = try paths.map {
      try FileCollector.collect(source: "struct Source {}", path: $0)
    }
    return PackageAnalysis(
      parsedCodebase: ParsedCodebase(rootPath: rootPath, files: files),
      manifest: PackageManifest(source: """
      import PackageDescription
      let package = Package(name: "Project", targets: [\(targets)])
      """),
      manifestInput: SourceCapture.Input(
        path: "/project/Package.swift",
        digest: nil
      )
    )
  }
}
