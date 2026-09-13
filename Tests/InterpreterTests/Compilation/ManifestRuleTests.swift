import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Interpreted package rules")
struct ManifestRuleTests {
  @Test("Undeclared and unused target dependencies fail the rule")
  func packageDependencies() async throws {
    let project = try packageDependencyProject(
      rulesFile: "Bylaws.swift",
      rulesSource: """
      let app = Codebase(including: ["Sources/**"])
      Rule("manifest", "Package dependencies match imports") {
        app.checkPackageDependencies()
      }
      """
    )

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    expectPackageDependencyFindings(findings)
  }

  @Test("An edge towards a freer target fails the stability rule")
  func dependencyStability() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": DependencyStabilityMock.manifest(
        toolsVersion: "6.2",
        packageName: "Example"
      ),
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("stability", "Dependencies point towards stability") {
        app.checkDependencyStability()
      }
      """,
      "Sources/Logging/Logging.swift": "struct Logging {}",
      "Sources/Utils/Utils.swift": "import Logging\nstruct Utils {}",
      "Sources/Core/Core.swift": "import Utils\nstruct Core {}",
      "Sources/Data/Data.swift": "import Core\nstruct Data {}",
      "Sources/UI/UI.swift": "import Core\nstruct UI {}",
    ])

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    #expect(findings.violations.count == 1)
    let offender = try #require(findings.violations.offenders.first)
    #expect(offender.name == "Core depends on Utils")
    #expect(
      offender.description == "Core (0.33) imports the freer Utils (0.50)"
    )
    #expect(findings.warnings.isEmpty)
  }

  @Test("An ignored target leaves the stability graph")
  func stabilityIgnoresATarget() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": DependencyStabilityMock.manifest(
        toolsVersion: "6.2",
        packageName: "Example"
      ),
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("stability", "Dependencies point towards stability") {
        app.checkDependencyStability(ignoring: ["Logging"])
      }
      """,
      "Sources/Logging/Logging.swift": "struct Logging {}",
      "Sources/Utils/Utils.swift": "import Logging\nstruct Utils {}",
      "Sources/Core/Core.swift": "import Utils\nstruct Core {}",
      "Sources/Data/Data.swift": "import Core\nstruct Data {}",
      "Sources/UI/UI.swift": "import Core\nstruct UI {}",
    ])

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    #expect(findings.violations.isEmpty)
    #expect(findings.warnings.isEmpty)
  }

  @Test("A stability check with a non-array argument produces a diagnostic")
  func stabilityArgumentDiagnoses() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(name: "Example", targets: [.target(name: "App")])
      """,
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("stability", "Dependencies point towards stability") {
        app.checkDependencyStability(ignoring: "Utils")
      }
      """,
      "Sources/App/App.swift": "struct App {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.rules.isEmpty)
    #expect(
      program.errors.contains {
        $0.message.contains(
          "'checkDependencyStability' takes one string array after 'ignoring:'"
        )
      }
    )
  }

  @Test("A duplicate target name produces a diagnostic")
  func duplicateTargetName() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [
          .target(name: "App", dependencies: ["Utils"]),
          .target(name: "Utils"),
          .target(name: "Utils"),
        ]
      )
      """,
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("stability", "Dependencies point towards stability") {
        app.checkDependencyStability()
      }
      """,
      "Sources/App/App.swift": "import Utils\nstruct App {}",
      "Sources/Utils/Utils.swift": "struct Utils {}",
    ])

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    #expect(findings.violations.isEmpty)
    #expect(findings.warnings.isEmpty)
  }

  @Test("A manifest the check cannot fully read warns the rule")
  func unresolvedManifestWarns() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [.target(name: "App")]
      )

      if Context.environment["EXTRA"] != nil {
        package.targets.append(.target(name: "Extra"))
      }
      """,
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("manifest", "Package dependencies match imports") {
        app.checkPackageDependencies()
      }
      """,
      "Sources/App/App.swift": "struct App {}",
    ])

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    #expect(findings.violations.isEmpty)
    #expect(
      findings.warnings.map(\.message) == [
        """
        Bylaws cannot read all of `targets` at line 10, column 3 in \
        Package.swift. This check may have missed dependencies.
        """,
        """
        Bylaws cannot read all of `targets` in Package.swift. This check \
        may have missed dependencies.
        """,
      ]
    )
  }

  @Test("An ignored target produces no empty-target warning")
  func ignoredTarget() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription

      let package = Package(
        name: "Example",
        targets: [
          .target(name: "App"),
          .target(name: "CModule"),
        ]
      )
      """,
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("manifest", "Package dependencies match imports") {
        app.checkPackageDependencies(ignoring: ["CModule"])
      }
      """,
      "Sources/App/App.swift": "struct App {}",
    ])

    let rule = try #require(
      await RuleProgram.discovered(atRoot: project.rootURL.path).rules.first
    )
    let findings = try await rule.findings()

    #expect(findings.violations.isEmpty)
    #expect(findings.warnings.isEmpty)
  }
}
