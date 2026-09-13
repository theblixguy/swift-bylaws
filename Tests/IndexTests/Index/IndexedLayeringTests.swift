import BylawsCore
import BylawsIndex
import BylawsIndexStore
import Testing

@Suite("Index-backed layering")
struct IndexedLayeringTests {
  @Test("A reference across a forbidden file layer is a violation")
  func forbiddenDependency() async throws {
    let project = try await testProject()
    let analyser = try IndexedLayeringAnalyser(
      layering: layering,
      parsedCodebase: project.codebase
    )

    let result = analyser.check(occurrenceGroups: [
      [
        reference(
          usr: "s:Model",
          name: "Model",
          file: project.domain,
          roles: .definition
        ),
        reference(
          usr: "s:Model",
          name: "Model",
          file: project.ui,
          line: 4,
          roles: .reference
        ),
      ],
    ])

    #expect(result.violations.checkedCount == 1)
    #expect(result.violations.offenders.map(\.name) == ["Model"])
  }

  @Test("An allowed index dependency satisfies a required edge")
  func allowedRequiredDependency() async throws {
    let project = try await testProject()
    let analyser = try IndexedLayeringAnalyser(
      layering: Layering(
        Layer("Domain", files: ["Sources/App/Domain/**"]),
        Layer(
          "UI",
          files: ["Sources/App/UI/**"],
          mustImport: ["Domain"]
        )
      ),
      parsedCodebase: project.codebase
    )

    let result = analyser.check(occurrenceGroups: [[
      reference(
        usr: "s:Model",
        name: "Model",
        file: project.domain,
        roles: .definition
      ),
      reference(
        usr: "s:Model",
        name: "Model",
        file: project.ui,
        roles: .reference
      ),
    ]])

    #expect(result.violations.isEmpty)
    #expect(result.missingImports.isEmpty)
  }

  @Test("Compiler-generated references do not create layer edges")
  func implicitReference() async throws {
    let project = try await testProject()
    let analyser = try IndexedLayeringAnalyser(
      layering: layering,
      parsedCodebase: project.codebase
    )

    let result = analyser.check(occurrenceGroups: [[
      reference(
        usr: "s:Model",
        name: "Model",
        file: project.domain,
        roles: .definition
      ),
      reference(
        usr: "s:Model",
        name: "Model",
        file: project.ui,
        roles: [.reference, .implicit]
      ),
    ]])

    #expect(result.violations.checkedCount == 0)
    #expect(result.violations.isEmpty)
  }

  @Test("An ambiguous symbol definition does not invent a dependency")
  func ambiguousDefinition() async throws {
    let project = try await testProject()
    let analyser = try IndexedLayeringAnalyser(
      layering: layering,
      parsedCodebase: project.codebase
    )

    let result = analyser.check(occurrenceGroups: [[
      reference(
        usr: "s:Shared",
        name: "Shared",
        file: project.domain,
        roles: .definition
      ),
      reference(
        usr: "s:Shared",
        name: "Shared",
        file: project.ui,
        roles: .definition
      ),
      reference(
        usr: "s:Shared",
        name: "Shared",
        file: project.ui,
        line: 5,
        roles: .reference
      ),
    ]])

    #expect(result.violations.checkedCount == 0)
    #expect(result.violations.isEmpty)
  }

  private var layering: Layering {
    Layering(
      Layer("Domain", files: ["Sources/App/Domain/**"]),
      Layer("UI", files: ["Sources/App/UI/**"])
    )
  }

  private func testProject() async throws -> (
    codebase: ParsedCodebase,
    domain: String,
    ui: String
  ) {
    let codebase = Codebase(
      root: .sources([
        "Sources/App/Domain/Model.swift": "struct Model {}",
        "Sources/App/UI/Screen.swift": "struct Screen {}",
      ]),
      including: ["Sources/**"]
    )
    let parsed = try await CodebaseCache.shared.parsedCodebase(for: codebase)
    return (
      parsed,
      "/virtual/Sources/App/Domain/Model.swift",
      "/virtual/Sources/App/UI/Screen.swift"
    )
  }

  private func reference(
    usr: String,
    name: String,
    file: String,
    line: Int = 1,
    roles: SymbolRole
  ) -> IndexReference {
    IndexReference(
      symbol: IndexSymbol(usr: usr, name: name, kind: .struct),
      module: "App",
      file: file,
      line: line,
      column: 3,
      roles: roles
    )
  }
}
