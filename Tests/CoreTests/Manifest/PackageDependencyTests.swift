import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Package dependency checking", .tags(.layering))
struct PackageDependencyTests {
  init() throws {
    project = try TemporaryProject(
      files: [
        "Package.swift": """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
          name: "App",
          targets: [
            .target(name: "Domain"),
            .target(name: "Data", dependencies: ["Domain", "Networking"]),
            .target(name: "Networking"),
            .target(name: "UI", dependencies: ["Domain"]),
          ]
        )
        """,
        "Sources/Domain/User.swift": "struct User {}",
        "Sources/Data/Store.swift": "import Domain\nimport Foundation",
        "Sources/Networking/Client.swift": "struct Client {}",
        "Sources/UI/HomeView.swift": "import Domain\nimport Data",
      ]
    )
  }

  @Test("An import without a declared dependency is undeclared")
  func undeclaredDependencyIsReported() async throws {
    let result = try await codebase.checkPackageDependencies()
    let entry = try #require(result.undeclared.first)
    #expect(result.undeclared.count == 1)
    #expect(entry.target == "UI")
    #expect(entry.module == "Data")
    #expect(entry.importDeclaration.location.fileName == "HomeView.swift")
    #expect(result.violations.offenders == [entry.importDeclaration])
    #expect(result.violations.checkedCount == result.checkedImportCount)
  }

  @Test("Findings report unused dependencies at the given location")
  func reportingLocation() async throws {
    let location = DeclarationLocation.start(of: "Bylaws.swift")
    let findings = try await codebase.checkPackageDependencies()
      .findings(reportedAt: location)
    let unused = try #require(
      findings.violations.offenders.first { $0.location == location }
    )
    #expect(unused.name == "Data depends on Networking")
    #expect(findings.violations.offenders.contains {
      $0.location.fileName == "HomeView.swift"
    })
  }

  @Test("Rules locate unused dependencies at their declaration")
  func ruleLocation() async throws {
    let codebase = codebase
    let rule = Rule("dependencies", "Package dependencies match imports") {
      try await codebase.checkPackageDependencies()
    }
    let findings = try await rule.findings()
    let unused = try #require(
      findings.violations.offenders.first {
        $0.name == "Data depends on Networking"
      }
    )
    #expect(unused.location == rule.location)
  }

  @Test("A declared dependency that no file imports is unused")
  func unusedDependencyIsReported() async throws {
    let result = try await codebase.checkPackageDependencies()
    #expect(result.unused == [
      PackageDependencyCheck.UnusedDependency(
        target: "Data", module: "Networking"
      ),
    ])
  }

  @Test("An import of another package is left alone")
  func ignoresModulesOutsideThePackage() async throws {
    let result = try await codebase.checkPackageDependencies()
    #expect(!result.undeclared.contains { $0.module == "Foundation" })
    #expect(result.checkedImportCount == 4)
  }

  @Test("The graph names each target's importers and imports")
  func reportsTheImportGraph() async throws {
    let graph = try await codebase.importGraph()
    let domain = try #require(graph.targets.first { $0.name == "Domain" })
    #expect(domain.importedBy == ["Data", "UI"])
    #expect(domain.imports.isEmpty)
    #expect(domain.instability == 0)

    let ui = try #require(graph.targets.first { $0.name == "UI" })
    #expect(ui.imports == ["Domain", "Data"])
    #expect(ui.importedBy.isEmpty)
    #expect(ui.instability == 1)
  }

  @Test("A target with no connections reports zero instability")
  func reportsIsolatedTarget() async throws {
    let graph = try await codebase.importGraph()
    let networking = try #require(
      graph.targets.first { $0.name == "Networking" }
    )
    #expect(networking.importedBy.isEmpty)
    #expect(networking.imports.isEmpty)
    #expect(networking.instability == 0)
  }

  @Test("Dependencies point towards stability")
  func dependenciesPointAtStability() async throws {
    let violations = try await codebase.checkDependencyStability().violations
    #expect(violations.isEmpty)
    #expect(violations.checkedCount == 3)
  }

  @Test("A target with no files in the codebase reports as empty")
  func emptyTargetIsReported() async throws {
    let sourcesOnly = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/Domain/**"]
    )
    let result = try await sourcesOnly.checkPackageDependencies()
    #expect(result.emptyTargets == ["Data", "Networking", "UI"])
  }

  @Test("Source and exclude paths select the files in a target")
  func respectsTargetSourceSelection() async throws {
    let selectedProject = try TemporaryProject(
      files: [
        "Package.swift": """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
          name: "App",
          targets: [
            .target(name: "Domain"),
            .target(name: "Other"),
            .target(
              name: "App",
              dependencies: ["Domain"],
              exclude: ["Included/Excluded.swift"],
              sources: ["Included"]
            ),
          ]
        )
        """,
        "Sources/Domain/Domain.swift": "struct Domain {}",
        "Sources/Other/Other.swift": "struct Other {}",
        "Sources/App/Included/App.swift": "import Domain",
        "Sources/App/Included/Excluded.swift": "import Other",
        "Sources/App/Ignored.swift": "import Other",
      ]
    )
    let selectedCodebase = Codebase(
      root: .directory(selectedProject.rootURL.path),
      including: ["Sources/**"]
    )

    let result = try await selectedCodebase.checkPackageDependencies()

    #expect(result.isComplete)
    #expect(result.undeclared.isEmpty)
    #expect(result.checkedImportCount == 1)
  }

  @Test("Unknown target sources make graph results incomplete")
  func reportsUnresolvedSourceSelection() async throws {
    let partialProject = try TemporaryProject(
      files: [
        "Package.swift": """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
          name: "App",
          targets: [.target(name: "App", sources: makeSources())]
        )
        """,
        "Sources/App/App.swift": "struct App {}",
      ]
    )
    let partialCodebase = Codebase(
      root: .directory(partialProject.rootURL.path),
      including: ["Sources/**"]
    )

    let dependencyCheck = try await partialCodebase
      .checkPackageDependencies()
    let stabilityCheck = try await partialCodebase
      .checkDependencyStability()
    let graph = try await partialCodebase.importGraph()

    #expect(!dependencyCheck.isComplete)
    #expect(!stabilityCheck.isComplete)
    #expect(!graph.isComplete)
  }

  @Test("A missing manifest reports an unreadable source")
  func missingManifest() async throws {
    let project = try TemporaryProject(
      files: ["Sources/App/App.swift": "struct App {}"]
    )
    let path = "\(project.rootURL.path)/Package.swift"
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    await #expect {
      _ = try await codebase.packageManifest
    } throws: { error in
      guard let error = error as? CodebaseError else { return false }
      guard case let .unreadable(failures) = error else { return false }
      return failures.count == 1
        && failures[0].path == path
        && !failures[0].reason.isEmpty
    }
  }

  @Test("A malformed manifest reports a parse failure")
  func malformedManifest() async throws {
    let project = try TemporaryProject(
      files: [
        "Package.swift": "let package = Package(",
        "Sources/App/App.swift": "struct App {}",
      ]
    )
    let path = "\(project.rootURL.path)/Package.swift"
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )

    await #expect(throws: CodebaseError.didNotParse(paths: [path])) {
      _ = try await codebase.packageManifest
    }
  }

  private let project: TemporaryProject

  private var codebase: Codebase {
    Codebase(root: .directory(project.rootURL.path), including: ["Sources/**"])
  }
}
