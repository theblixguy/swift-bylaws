import Bylaws

extension Codebase {
  static let bylaws = Codebase(
    root: .automatic(),
    including: ["Sources/**"],
    swiftLanguageMode: .v6
  )

  static let bylawsTests = Codebase(
    root: .automatic(),
    including: ["Tests/**"],
    excluding: generatedAndDeliberatelyInvalidTestPaths,
    swiftLanguageMode: .v6
  )

  private static let generatedAndDeliberatelyInvalidTestPaths: [Glob] = [
    "**/.build/**",
    "Tests/SampleApp/**",
  ]
}
