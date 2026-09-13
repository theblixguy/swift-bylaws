import Bylaws
import BylawsTestSupport
import Foundation
import Testing

@Suite("Layering", .tags(.layering))
struct LayeringTests {
  init() throws {
    project = try TemporaryProject(
      files: [
        "Sources/Domain/User.swift": "struct User {}",
        "Sources/Data/UserStore.swift": "import Domain\nimport Foundation",
        "Sources/UI/HomeView.swift": "import Domain\nimport Data\nimport SwiftUI",
      ]
    )
  }

  @Test("An undeclared edge between layers is a violation")
  func undeclaredEdgeFails() async throws {
    let result = try await codebase.checkLayering(layering)
    let offender = try #require(result.violations.offenders.first)
    #expect(result.violations.count == 1)
    #expect(offender.moduleName == "Data")
    #expect(offender.location.fileName == "HomeView.swift")
  }

  @Test("Allowed and undeclared imports pass")
  func allowedEdgesPass() async throws {
    let result = try await codebase.checkLayering(layering)
    let offenderModules = result.violations.offenders.map(\.moduleName)
    #expect(!offenderModules.contains("Domain"))
    #expect(!offenderModules.contains("Foundation"))
    #expect(!offenderModules.contains("SwiftUI"))
    #expect(result.violations.checkedCount == 5)
  }

  @Test(
    "An edge name without a declared layer throws",
    arguments: UnknownLayerCase.cases
  )
  func unknownLayerThrows(_ testCase: UnknownLayerCase) async throws {
    let wrong = Layering(testCase.layer)
    await #expect(throws: LayeringCheckError.invalidLayering(.unknownLayer(
      name: "Domian", allowedBy: testCase.allowedBy
    ))) {
      try await codebase.checkLayering(wrong)
    }
  }

  @Test("Two layers declaring the same module throw")
  func duplicateModuleThrows() async throws {
    let wrong = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Core", files: ["Sources/Core/**"], modules: ["Domain"])
    )
    await #expect(throws: LayeringCheckError.invalidLayering(.duplicateModule(
      name: "Domain", layers: ["Domain", "Core"]
    ))) {
      try await codebase.checkLayering(wrong)
    }
  }

  @Test("Two layers with the same name throw")
  func duplicateLayerThrows() async throws {
    let wrong = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Domain", files: ["Sources/Data/**"], modules: ["Data"])
    )
    await #expect(throws: LayeringCheckError
      .invalidLayering(.duplicateLayer(name: "Domain")))
    {
      try await codebase.checkLayering(wrong)
    }
  }

  @Test("A file matching two layers' globs throws")
  func overlappingLayersThrow() async throws {
    let wrong = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Everything", files: ["Sources/**"], modules: ["App"])
    )
    await #expect(throws: LayeringCheckError.invalidLayering(.overlappingLayers(
      file: "Sources/Domain/User.swift", layers: ["Domain", "Everything"]
    ))) {
      try await codebase.checkLayering(wrong)
    }
  }

  @Test("A layer that matches no files is reported as empty")
  func emptyLayerIsReported() async throws {
    let withGhost = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Networking", files: ["Sources/Networking/**"])
    )
    let result = try await codebase.checkLayering(withGhost)
    #expect(result.emptyLayers == ["Networking"])
  }

  @Test("A used mustImport edge is allowed")
  func usedRequiredEdgePasses() async throws {
    let strict = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Data", files: ["Sources/Data/**"], mustImport: ["Domain"])
    )
    let result = try await codebase.checkLayering(strict)
    #expect(result.missingImports.isEmpty)
    let offenderModules = result.violations.offenders.map(\.moduleName)
    #expect(!offenderModules.contains("Domain"))
  }

  @Test("A mustImport edge that no file uses is reported as missing")
  func unusedRequiredEdgeIsMissing() async throws {
    let strict = Layering(
      Layer("Domain", files: ["Sources/Domain/**"], mustImport: ["Data"]),
      Layer("Data", files: ["Sources/Data/**"], mayImport: .any)
    )
    let result = try await codebase.checkLayering(strict)
    #expect(result.missingImports == [
      LayeringCheck.MissingImport(layer: "Domain", requiredImport: "Data"),
    ])
  }

  @Test("Layering findings include violations, missing edges and empty layers")
  func findingsReportEveryResult() async throws {
    let strict = Layering(
      Layer("Domain", files: ["Sources/Domain/**"], mustImport: ["Data"]),
      Layer("Data", files: ["Sources/Data/**"]),
      Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"]),
      Layer("Widgets", files: ["Sources/Widgets/**"])
    )
    let findings = try await codebase.checkLayering(strict)
      .findings(reportedAt: .start(of: #filePath))
    let names = findings.violations.offenders.compactMap(\.name).sorted()
    #expect(names == ["Data", "Domain", "Domain imports Data"])
    #expect(findings.warnings.map(\.message) == [
      "layer 'Widgets' matched no files",
    ])
    #expect(findings.warnings.first?.location.fileName == "LayeringTests.swift")
  }

  @Test("A layer can declare module names that differ from its name")
  func modulesParameterMapsImports() async throws {
    let renamed = Layering(
      Layer("Domain", files: ["Sources/Domain/**"], modules: ["Domain"]),
      Layer(
        "Interface", files: ["Sources/UI/**"], modules: ["UI", "SwiftUI"]
      )
    )
    let result = try await codebase.checkLayering(renamed)
    let offenderModules = result.violations.offenders.map(\.moduleName)
    #expect(offenderModules.contains("SwiftUI") == false)
    #expect(offenderModules.contains("Domain"))
  }

  @Test("A layer that may import anything only fails on a banned edge")
  func deniedEdgeFailsUnderAnyLayer() async throws {
    let permissive = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Data", files: ["Sources/Data/**"], mayImport: .any),
      Layer(
        "UI",
        files: ["Sources/UI/**"],
        mayImport: .any,
        mustNotImport: ["Data"]
      )
    )
    let result = try await codebase.checkLayering(permissive)
    let offenders = result.violations.offenders
    #expect(offenders.map(\.moduleName) == ["Data"])
    let offender = try #require(offenders.first)
    #expect(offender.location.fileName == "HomeView.swift")
  }

  @Test("A layer that may and must not import a layer throws")
  func contradictoryImportThrows() async throws {
    let wrong = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer(
        "UI",
        files: ["Sources/UI/**"],
        mayImport: ["Domain"],
        mustNotImport: ["Domain"]
      )
    )
    await #expect(throws: LayeringCheckError
      .invalidLayering(.contradictoryImport(
        layer: "UI",
        target: "Domain"
      )))
    {
      try await codebase.checkLayering(wrong)
    }
  }

  @Test("A cycle in the declared imports throws")
  func circularLayersThrow() async throws {
    let wrong = Layering(
      Layer("Domain", files: ["Sources/Domain/**"], mayImport: ["Data"]),
      Layer("Data", files: ["Sources/Data/**"], mayImport: ["Domain"])
    )
    await #expect(throws: LayeringCheckError.invalidLayering(.circularLayers(
      path: ["Domain", "Data", "Domain"]
    ))) {
      try await codebase.checkLayering(wrong)
    }
  }

  private let project: TemporaryProject

  private var codebase: Codebase {
    Codebase(root: .directory(project.rootURL.path))
  }

  private var layering: Layering {
    Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Data", files: ["Sources/Data/**"], mayImport: ["Domain"]),
      Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
    )
  }

  struct UnknownLayerCase: Sendable, CustomTestStringConvertible {
    let allowedBy: String
    let layer: Layer

    var testDescription: String { allowedBy }

    static let cases = [
      UnknownLayerCase(
        allowedBy: "UI",
        layer: Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domian"])
      ),
      UnknownLayerCase(
        allowedBy: "Domain",
        layer: Layer(
          "Domain",
          files: ["Sources/Domain/**"],
          mustImport: ["Domian"]
        )
      ),
    ]
  }
}
