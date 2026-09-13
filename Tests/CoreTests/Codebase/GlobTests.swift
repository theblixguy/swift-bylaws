import Bylaws
import Testing

@Suite("Glob matching")
struct GlobTests {
  @Test("Patterns match root-relative paths", arguments: matchCases)
  func matches(pattern: String, path: String, expected: Bool) {
    #expect(Glob(pattern).matches(path) == expected)
  }

  @Test(
    "Patterns identify directories that can contain a match",
    arguments: descendantCases
  )
  func canMatchDescendant(pattern: String, directory: String, expected: Bool) {
    #expect(
      Glob(pattern).canMatchDescendant(of: Glob.Path(directory)) == expected
    )
  }

  @Test("Matching descendant keeps directory available")
  func matchingDescendantKeepsDirectoryAvailable() {
    let patterns = Self.paths(segments: ["a", "*", "**"], maximumLength: 3)
    let directories = Self.paths(segments: ["a", "b"], maximumLength: 2)
    let suffixes = Self.paths(
      segments: ["a", "b"],
      minimumLength: 1,
      maximumLength: 4
    )

    for pattern in patterns {
      let glob = Glob(pattern)
      for directory in directories {
        let hasMatchingDescendant = suffixes.contains { suffix in
          let descendant = directory.isEmpty
            ? suffix
            : "\(directory)/\(suffix)"
          return glob.matches(descendant)
        }
        if hasMatchingDescendant {
          #expect(glob.canMatchDescendant(of: Glob.Path(directory)))
        }
      }
    }
  }

  @Test("Repeated star patterns match quickly", .timeLimit(.minutes(1)))
  func repeatedStarPatternMatchesQuickly() {
    let glob = Glob("*a*a*a*a*a*a*a*a*a*a*a*a*b")
    #expect(!glob.matches(String(repeating: "a", count: 60)))
  }

  private static let matchCases: [
    (pattern: String, path: String, expected: Bool)
  ] = [
    (pattern: "Package.swift", path: "Package.swift", expected: true),
    (pattern: "Package.swift", path: "App/Package.swift", expected: false),
    (
      pattern: "**/Generated/**",
      path: "App/Generated/Model.swift",
      expected: true
    ),
    (pattern: "**/Generated/**", path: "Generated/Model.swift", expected: true),
    (
      pattern: "**/Generated/**",
      path: "App/Handwritten/Model.swift",
      expected: false
    ),
    (
      pattern: "Sources/**",
      path: "Sources/App/Deep/File.swift",
      expected: true
    ),
    (pattern: "Sources/**", path: "Tests/AppTests/File.swift", expected: false),
    (pattern: "*.swift", path: "File.swift", expected: true),
    (pattern: "*.swift", path: "App/File.swift", expected: false),
    (
      pattern: "App/*ViewModel.swift",
      path: "App/HomeViewModel.swift",
      expected: true
    ),
    (pattern: "App/*ViewModel.swift", path: "App/Home.swift", expected: false),
    (pattern: "App/?.swift", path: "App/A.swift", expected: true),
    (pattern: "App/?.swift", path: "App/AB.swift", expected: false),
  ]

  private static let descendantCases: [
    (pattern: String, directory: String, expected: Bool)
  ] = [
    (pattern: "Sources/**", directory: "Sources", expected: true),
    (pattern: "Sources/**", directory: "Tests", expected: false),
    (pattern: "Sources/*.swift", directory: "Sources", expected: true),
    (pattern: "Sources/*.swift", directory: "Sources/Feature", expected: false),
    (pattern: "**/Generated/**", directory: "Sources", expected: true),
    (pattern: "Modules/*/Sources/**", directory: "Modules/App", expected: true),
    (
      pattern: "Modules/*/Sources/**",
      directory: "Modules/App/Tests",
      expected: false
    ),
    (pattern: "Package.swift", directory: "Package.swift", expected: false),
  ]

  private static func paths(
    segments: [String],
    minimumLength: Int = 0,
    maximumLength: Int
  ) -> [String] {
    (minimumLength...maximumLength).flatMap { length in
      products(of: segments, count: length).map { $0.joined(separator: "/") }
    }
  }

  private static func products(
    of values: [String],
    count: Int
  ) -> [[String]] {
    guard count > 0 else { return [[]] }
    return products(of: values, count: count - 1).flatMap { prefix in
      values.map { prefix + [$0] }
    }
  }
}
