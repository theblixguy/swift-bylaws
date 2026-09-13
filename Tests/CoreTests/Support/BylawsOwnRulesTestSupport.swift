import Bylaws

extension Codebase {
  static let bylaws = Codebase(
    root: .automatic(),
    including: ["Sources/**"]
  )

  static let bylawsTests = Codebase(
    root: .automatic(),
    including: ["Tests/**"],
    excluding: generatedAndDeliberatelyInvalidTestPaths
  )

  private static let generatedAndDeliberatelyInvalidTestPaths: [Glob] = [
    "**/.build/**",
    "Tests/SampleApp/**",
  ]
}
