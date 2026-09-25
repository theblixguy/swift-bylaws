import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite(
  "Codebase index queries",
  .enabled(
    if: IndexUnderTest.isAvailable,
    "This build wrote no index store. Build in debug first."
  ),
  .tags(.indexStore)
)
struct CodebaseIndexTests {
  @Test("Index matches a symlinked codebase root")
  func indexMatchesSymlinkedRoot() async throws {
    let project = try TemporaryProject(files: [:])
    let alias = project.fileURL(for: "linked-package")
    let root = try IndexUnderTest.codebase.resolvedRootPath()
    try FileManager.default.createSymbolicLink(
      at: alias,
      withDestinationURL: URL(fileURLWithPath: root)
    )
    let codebase = Codebase(
      root: .directory(alias.path),
      including: ["Tests/TestModules/PortableRuleSupport/Subjects.swift"],
      swiftLanguageMode: .v6
    )

    let source = try #require(await codebase.files.first)
    #expect(source.path.hasPrefix(alias.path))
    let index = try await codebase.projectIndex()
    let definition = try #require(index.definitions(of: "SupportSubject").first)
    let moduleIndex = try await codebase.projectIndex(
      modules: ["PortableRuleSupport"]
    )
    let moduleDefinition = try #require(
      moduleIndex.definitions(of: "SupportSubject").first
    )

    #expect(index.fileCount == 1)
    #expect(definition.file == source.path)
    #expect(moduleDefinition.file == source.path)
  }

  @Test("Index follows codebase file selection")
  func indexUsesSelectedFiles() async throws {
    let selected = Codebase(
      root: .automatic(),
      including: ["Tests/TestModules/PortableRuleSupport/Subjects.swift"],
      swiftLanguageMode: .v6
    )

    let index = try await selected.projectIndex()

    #expect(index.modules == ["PortableRuleSupport"])
    #expect(index.fileCount == 1)
    #expect(!index.definitions(of: "SupportSubject").isEmpty)
    #expect(index.definitions(of: "SourceLocationCalls").isEmpty)
  }

  @Test("Index reads files across selected modules")
  func indexIncludesSelectedModules() async throws {
    let selected = Codebase(
      root: .automatic(),
      including: ["Tests/TestModules/PortableR*/**"],
      excluding: ["**/SourceLocationCalls.swift"],
      swiftLanguageMode: .v6
    )

    let index = try await selected.projectIndex()

    #expect(index.modules == testModuleNames)
    #expect(index.definitions(of: "SourceLocationCalls").isEmpty)
    #expect(!index.definitions(of: "SupportSubject").isEmpty)
  }

  @Test("Selected files resolve standard protocol conformances")
  func selectedFilesResolveExternalProtocols() async throws {
    let selected = Codebase(
      root: .automatic(),
      including: ["Sources/BylawsIndexStore/**"],
      swiftLanguageMode: .v6
    )

    let conformers = try await selected.conformers(of: "Sendable")

    #expect(conformers.contains { $0.symbol.name == "IndexSymbol" })
  }

  @Test("Explicit modules replace codebase file selection")
  func explicitModulesOverrideFiles() async throws {
    let selected = Codebase(
      root: .automatic(),
      including: ["Tests/TestModules/PortableRuleSupport/Subjects.swift"],
      swiftLanguageMode: .v6
    )

    let index = try await selected
      .projectIndex(modules: ["PortableRuleSupport"])

    #expect(!index.definitions(of: "SourceLocationCalls").isEmpty)
  }

  @Test("Different file selections read separate indexes")
  func differentSelectionsUseSeparateCacheEntries() async throws {
    let cache = ProjectIndexCache()
    let first = Codebase(
      root: .automatic(),
      including: ["Tests/TestModules/PortableRuleSupport/Subjects.swift"],
      swiftLanguageMode: .v6
    )
    let second = Codebase(
      root: .automatic(),
      including: ["Tests/TestModules/PortableRuleSupport/Matchers.swift"],
      swiftLanguageMode: .v6
    )

    _ = try await cache.index(for: first, modules: nil, unitOutputFiles: nil)
    _ = try await cache.index(for: second, modules: nil, unitOutputFiles: nil)

    #expect(await cache.readCount == 2)
  }

  @Test("A codebase opens the index from its build")
  func readsTheIndex() async throws {
    let index = try await codebase.projectIndex(modules: ourModules)
    #expect(index.modules.contains("BylawsCore"))
  }

  @Test("A codebase returns conformers from its index")
  func findsConformers() async throws {
    let conformers = try await testModules.conformers(
      of: "PortableSubject",
      modules: testModuleNames
    )
    #expect(
      Set(conformers.map(\.symbol.name)) == [
        "NamedPortableSubject", "SupportSubject", "RuleSubject",
      ]
    )
  }

  @Test("A codebase returns references from its index")
  func findsReferences() async throws {
    let users = try await testModules.references(
      to: "hasAtMostOneFunction(_:)",
      modules: testModuleNames
    )
    #expect(!users.isEmpty)
    #expect(Set(users.map(\.module)) == ["PortableRules"])
  }

  @Test("A codebase returns direct conformers from its index")
  func findsDirectConformers() async throws {
    let direct = try await testModules.directConformers(
      of: "PortableSubject",
      modules: testModuleNames
    )
    #expect(
      Set(direct.map(\.symbol.name)) == ["NamedPortableSubject", "RuleSubject"]
    )
  }

  @Test("A codebase returns definitions and occurrences from its index")
  func findsDefinitionsAndOccurrences() async throws {
    let index = try await testModules.projectIndex(modules: testModuleNames)
    let definitions = try await testModules.definitions(
      of: "hasAtMostOneFunction(_:)",
      modules: testModuleNames
    )
    let occurrences = try await testModules.occurrences(
      of: "hasAtMostOneFunction(_:)",
      modules: testModuleNames
    )
    #expect(!definitions.isEmpty)
    #expect(occurrences.count > definitions.count)
    #expect(definitions == index.definitions(of: "hasAtMostOneFunction(_:)"))
    #expect(occurrences == index.occurrences(of: "hasAtMostOneFunction(_:)"))
  }

  @Test("A second query reuses the loaded index")
  func sharesOneRead() async throws {
    let cache = ProjectIndexCache()
    _ = try await IndexUnderTest.index(through: cache)
    _ = try await IndexUnderTest.index(through: cache)
    #expect(await cache.readCount == 1)
  }

  @Test("Removing a project from the cache reloads its index")
  func reloadsAfterRemoval() async throws {
    let cache = ProjectIndexCache()
    _ = try await IndexUnderTest.index(through: cache)

    let root = try IndexUnderTest.codebase.resolvedRootPath()
    await cache.removeEntries(under: root)
    _ = try await IndexUnderTest.index(through: cache)

    #expect(await cache.readCount == 2)
  }

  @Test("Removing another project leaves the cached index in place")
  func keepsUnrelatedEntries() async throws {
    let cache = ProjectIndexCache()
    _ = try await IndexUnderTest.index(through: cache)

    await cache.removeEntries(under: "/nowhere/this/project/lives")
    _ = try await IndexUnderTest.index(through: cache)

    #expect(await cache.readCount == 1)
  }

  @Test("Concurrent queries share one index store read")
  func sharesOneReadAcrossCallers() async throws {
    let cache = ProjectIndexCache()

    async let first = IndexUnderTest.index(through: cache)
    async let second = IndexUnderTest.index(through: cache)
    _ = try await (first, second)

    #expect(await cache.readCount == 1)
  }

  @Test("A codebase checks file layers with its compiler index")
  func checksFileLayers() async throws {
    let layering = Layering(
      Layer(
        "Matchers",
        files: ["Tests/TestModules/PortableRules/Matchers/**"]
      ),
      Layer("Rules", files: ["Tests/TestModules/PortableRules/Rules/**"])
    )

    let findings = try await testModules.indexedFindings(
      of: layering,
      modules: ["PortableRules"]
    )

    #expect(!findings.violations.isEmpty)
    #expect(
      findings.violations.offenders.contains {
        $0.description.contains("layer 'Rules' depends on layer 'Matchers'")
      }
    )

    let violations = try await testModules.indexedViolations(
      of: layering,
      modules: ["PortableRules"]
    )
    #expect(violations == findings.violations)
  }

  @Test("A name the index does not hold reports a warning")
  func unknownSymbolNameWarns() async throws {
    let (references, warnings) = try await QueryWarnings.collecting {
      try await testModules.references(
        to: "hasAtMostOneFunctionn(_:)",
        modules: testModuleNames
      )
    }

    #expect(references.isEmpty)
    #expect(warnings.map(\.message) == [
      "'hasAtMostOneFunctionn(_:)' names no indexed symbol",
    ])
  }

  @Test("A name the index holds reports no warning")
  func knownSymbolNameIsQuiet() async throws {
    let (references, warnings) = try await QueryWarnings.collecting {
      try await testModules.references(
        to: "hasAtMostOneFunction(_:)",
        modules: testModuleNames
      )
    }

    #expect(!references.isEmpty)
    #expect(warnings.isEmpty)
  }

  private let codebase = IndexUnderTest.codebase
  private let ourModules = IndexUnderTest.modules
  private let testModules = IndexUnderTest.testModules
  private let testModuleNames = IndexUnderTest.testModuleNames
}
