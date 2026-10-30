import Bylaws
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsCore

@Suite("Codebase cache removal")
struct CodebaseCacheEvictionTests {
  @Test("Removal selects descendants and keeps sibling and inline roots")
  func directoryBoundaries() async throws {
    let project = try TemporaryProject(files: [
      "App/Model.swift": "struct RootBefore {}",
      "App/Child/Model.swift": "struct ChildBefore {}",
      "AppExtra/Model.swift": "struct SiblingBefore {}",
    ])
    let cache = CodebaseCache()
    let root = Codebase(
      root: .directory(project.rootURL.appendingPathComponent("App").path),
      swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    let child = Codebase(
      root: .directory(project.rootURL.appendingPathComponent("App/Child")
        .path),
      swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    let sibling = Codebase(
      root: .directory(project.rootURL.appendingPathComponent("AppExtra").path),
      swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    let inline = Codebase(
      root: .sources(["Model.swift": "struct Inline {}"]),
      swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    #expect(try await names(in: root, using: cache) == [
      "ChildBefore",
      "RootBefore",
    ])
    #expect(try await names(in: child, using: cache) == ["ChildBefore"])
    #expect(try await names(in: sibling, using: cache) == ["SiblingBefore"])
    #expect(try await names(in: inline, using: cache) == ["Inline"])
    #expect(await cache.cachedConfigurationCount == 4)

    try "struct RootAfter {}".write(
      to: project.rootURL.appendingPathComponent("App/Model.swift"),
      atomically: true, encoding: .utf8
    )
    try "struct ChildAfter {}".write(
      to: project.rootURL.appendingPathComponent("App/Child/Model.swift"),
      atomically: true, encoding: .utf8
    )
    try "struct SiblingAfter {}".write(
      to: project.rootURL.appendingPathComponent("AppExtra/Model.swift"),
      atomically: true, encoding: .utf8
    )
    await cache.removeEntries(
      under: project.rootURL.path + "/App/Child/../."
    )

    #expect(await cache.cachedConfigurationCount == 2)
    #expect(try await names(in: root, using: cache) == [
      "ChildAfter",
      "RootAfter",
    ])
    #expect(try await names(in: child, using: cache) == ["ChildAfter"])
    #expect(try await names(in: sibling, using: cache) == ["SiblingBefore"])
    #expect(try await names(in: inline, using: cache) == ["Inline"])
    #expect(await cache.cachedConfigurationCount == 4)
  }

  @Test("Removal clears each lookup for shared directory entries")
  func sharedCanonicalEntry() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Model.swift": "struct Before {}",
    ])
    let cache = CodebaseCache()
    let directory = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    let automatic = Codebase(
      root: .automatic(above: project.rootURL
        .appendingPathComponent("Model.swift").path),
      swiftLanguageMode: .v6
    ).usingParseCache(.disabled)
    #expect(try await names(in: directory, using: cache) == ["Before"])
    try "struct After {}".write(
      to: project.rootURL.appendingPathComponent("Model.swift"),
      atomically: true, encoding: .utf8
    )
    #expect(try await names(in: automatic, using: cache) == ["Before"])
    #expect(await cache.cachedConfigurationCount == 2)

    await cache.removeEntries(under: project.rootURL.path)

    #expect(await cache.cachedConfigurationCount == 0)
    #expect(try await names(in: directory, using: cache) == ["After"])
    #expect(try await names(in: automatic, using: cache) == ["After"])
    #expect(await cache.cachedConfigurationCount == 2)
  }

  private func names(
    in codebase: Codebase,
    using cache: CodebaseCache
  ) async throws -> [String] {
    let parsed = try await cache.parsedCodebase(for: codebase)
    return parsed.filesAsWritten.flatMap(\.structs).map(\.name).sorted()
  }
}
