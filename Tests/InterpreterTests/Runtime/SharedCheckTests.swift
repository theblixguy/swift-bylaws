import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Compiled and interpreted check results")
struct SharedCheckTests {
  private let project: TemporaryProject

  init() throws {
    project = try packageDependencyProject(
      rulesFile: "ProjectRules.swift",
      rulesSource: ""
    )
    try project.write("""
    // swift-tools-version: 6.2
    import PackageDescription
    let package = Package(name: "App", targets: [
      .target(name: "App", dependencies: ["Unused"]),
      .target(name: "Domain"),
      .target(name: "Unused"),
      .target(name: "Empty"),
      .target(name: "Unknown", dependencies: configuredDependencies),
    ])
    """, to: "Package.swift")
  }

  @Test(
    "Package checks return equal findings",
    arguments: [Enforcement.enforced, .advisory]
  )
  func package(enforcement: Enforcement) async throws {
    let interpretedRule = try await interpretedRule(
      call: "sharedPackageCheck(app)",
      enforcement: enforcement
    )
    let codebase = codebase
    let nativeRule = Rule(
      "shared",
      "Checks agree",
      enforcement: enforcement,
      location: interpretedRule.location
    ) {
      try await sharedPackageCheck(codebase)
    }
    let native = try await nativeRule.findings()
    let interpreted = try await interpretedRule.findings()

    #expect(interpretedRule.enforcement == enforcement)
    #expect(nativeRule.enforcement == enforcement)
    #expect(interpreted.violations == native.violations)
    #expect(interpreted.warnings == native.warnings)
    #expect(native.violations.count == 2)
    #expect(native.warnings.count == 3)
  }

  @Test(
    "Stability checks return equal findings",
    arguments: [Enforcement.enforced, .advisory]
  )
  func stability(enforcement: Enforcement) async throws {
    let interpretedRule = try await interpretedRule(
      call: "sharedStabilityCheck(app)",
      enforcement: enforcement
    )
    let codebase = codebase
    let nativeRule = Rule(
      "shared",
      "Checks agree",
      enforcement: enforcement,
      location: interpretedRule.location
    ) {
      try await sharedStabilityCheck(codebase)
    }
    let native = try await nativeRule.findings()
    let interpreted = try await interpretedRule.findings()

    #expect(interpretedRule.enforcement == enforcement)
    #expect(nativeRule.enforcement == enforcement)
    #expect(interpreted.violations == native.violations)
    #expect(interpreted.warnings == native.warnings)
    #expect(native.violations.isEmpty)
    #expect(native.warnings.count == 3)
  }

  @Test(
    "Layering checks return equal findings",
    arguments: [Enforcement.enforced, .advisory]
  )
  func layering(enforcement: Enforcement) async throws {
    let interpretedRule = try await interpretedRule(
      call: "sharedLayeringCheck(app, layers)",
      enforcement: enforcement,
      declarations: """
      let layers = Layering(
        Layer("App", files: ["Sources/App/**"]),
        Layer("Domain", files: ["Sources/Domain/**"], mustImport: ["Unused"]),
        Layer("Unused", files: ["Sources/Unused/**"]),
        Layer("Empty", files: ["Sources/Empty/**"])
      )
      """
    )
    let codebase = codebase
    let layers = Layering(
      Layer("App", files: ["Sources/App/**"]),
      Layer("Domain", files: ["Sources/Domain/**"], mustImport: ["Unused"]),
      Layer("Unused", files: ["Sources/Unused/**"]),
      Layer("Empty", files: ["Sources/Empty/**"])
    )
    let nativeRule = Rule(
      "shared",
      "Checks agree",
      enforcement: enforcement,
      location: interpretedRule.location
    ) {
      try await sharedLayeringCheck(codebase, layers)
    }
    let native = try await nativeRule.findings()
    let interpreted = try await interpretedRule.findings()

    #expect(interpretedRule.enforcement == enforcement)
    #expect(nativeRule.enforcement == enforcement)
    #expect(interpreted.violations == native.violations)
    #expect(interpreted.warnings == native.warnings)
    #expect(native.violations.count == 2)
    #expect(native.warnings.count == 1)
  }

  @Test(
    "Result helpers preserve counts and warnings",
    arguments: [Enforcement.enforced, .advisory]
  )
  func resultFields(enforcement: Enforcement) async throws {
    let interpretedRule = try await interpretedRule(
      call: "sharedResultFields(app)",
      enforcement: enforcement
    )
    let codebase = codebase
    let nativeRule = Rule(
      "shared",
      "Checks agree",
      enforcement: enforcement,
      location: interpretedRule.location
    ) {
      try await sharedResultFields(codebase)
    }
    let native = try await nativeRule.findings()
    let interpreted = try await interpretedRule.findings()

    #expect(interpretedRule.enforcement == enforcement)
    #expect(nativeRule.enforcement == enforcement)
    #expect(interpreted.violations == native.violations)
    #expect(interpreted.warnings == native.warnings)
    #expect(native.violations.isEmpty)
    #expect(native.warnings.isEmpty)
  }

  private var codebase: Codebase {
    Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
  }

  private func interpretedRule(
    call: String,
    enforcement: Enforcement,
    declarations: String = ""
  ) async throws -> Rule {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Support/PortableCheckRules.swift")
    let helpers = try String(contentsOf: sourceURL, encoding: .utf8)
    try project.write("""
    \(helpers)
    let app = Codebase(including: ["Sources/**"])
    \(declarations)
    let projectRules: [Rule] = [
      Rule("shared", "Checks agree", enforcement: .\(enforcement.rawValue)) {
        try await \(call)
      }
    ]
    """, to: "ProjectRules.swift")
    let program = try await loadedProgram(in: project)
    return try #require(program.rules.first)
  }
}
