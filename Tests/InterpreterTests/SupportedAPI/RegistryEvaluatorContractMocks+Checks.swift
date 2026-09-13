import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
@testable import BylawsInterpreter

extension ContractMocks {
  static func checkResults() async throws -> [RuntimeCheckValue] {
    let project = try TemporaryProject(files: [
      "Package.swift": """
      // swift-tools-version: 6.2
      import PackageDescription
      let package = Package(name: "App", targets: [
        .target(name: "App", dependencies: ["Unused"]),
        .target(name: "Domain"),
        .target(name: "Leaf"),
        .target(name: "Unused"),
        .target(name: "ClientA"),
        .target(name: "ClientB"),
        .target(name: "Empty"),
        .target(name: "Unknown", dependencies: configuredDependencies),
      ])
      """,
      "Sources/App/App.swift": "import Domain",
      "Sources/Domain/Domain.swift": "import Leaf",
      "Sources/Leaf/Leaf.swift": "struct Leaf {}",
      "Sources/Unused/Unused.swift": "struct Unused {}",
      "Sources/ClientA/Client.swift": "import App",
      "Sources/ClientB/Client.swift": "import App",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let dependencies = try await codebase.checkPackageDependencies()
    let stability = try await codebase.checkDependencyStability()
    let layers = try await codebase.checkLayering(Layering(
      Layer("App", files: ["Sources/App/**"]),
      Layer("Domain", files: ["Sources/Domain/**"], mustImport: ["Unused"]),
      Layer("Unused", files: ["Sources/Unused/**"]),
      Layer("Empty", files: ["Sources/Empty/**"])
    ))
    let folders = try await codebase.checkFolderLayout(
      matching: "Sources", containing: ["Missing"]
    )
    let location = DeclarationLocation(
      filePath: "/Project/Bylaws.swift", line: 3, column: 1, utf8Offset: 42
    )
    return [
      .packageDependencies(dependencies),
      .dependencyStability(stability),
      .layering(layers),
      .folderLayout(folders),
      .location(location),
    ]
      + dependencies.undeclared.map(RuntimeCheckValue.undeclaredDependency)
      + dependencies.unused.map(RuntimeCheckValue.unusedDependency)
      + stability.unstable.map(RuntimeCheckValue.unstableDependency)
      + layers.missingImports.map(RuntimeCheckValue.missingImport)
      + dependencies.findings(reportedAt: location).warnings
      .map(RuntimeCheckValue.warning)
  }
}
