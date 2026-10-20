import BylawsCore
import BylawsIndexStore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsIndex

@Suite("Correction index selection", .tags(.indexStore))
struct CorrectionIndexSelectionTests {
  @Test("Normal queries preserve index discovery")
  func normalDiscovery() async throws {
    let path = try await ProjectIndexCache.correctionIndexStore(
      forRoot: "/virtual/App", environment: [:]
    )

    #expect(path == nil)
  }

  @Test("Correction selects matching fresh index")
  func matchingRoot() async throws {
    let path = try await ProjectIndexCache.correctionIndexStore(
      forRoot: "/virtual/App",
      environment: [
        "BYLAWS_CORRECTION_ACTIVE": "1",
        "BYLAWS_FRESH_INDEX_ROOT": "/virtual/App",
        "BYLAWS_FRESH_INDEX_STORE": "/virtual/build/index/store",
      ]
    )

    #expect(path == "/virtual/build/index/store")
  }

  @Test("Correction matches symbolic root aliases")
  func matchingRootAlias() async throws {
    let project = try TemporaryProject(files: [:])
    let alias = project.fileURL(for: "alias")
    try FileManager.default.createSymbolicLink(
      at: alias, withDestinationURL: project.rootURL
    )
    let path = try await ProjectIndexCache.correctionIndexStore(
      forRoot: alias.path,
      environment: [
        "BYLAWS_CORRECTION_ACTIVE": "1",
        "BYLAWS_FRESH_INDEX_ROOT": project.rootURL.path,
        "BYLAWS_FRESH_INDEX_STORE": "/virtual/build/index/store",
      ]
    )

    #expect(path == "/virtual/build/index/store")
  }

  @Test(
    "Correction rejects missing or mismatched fresh index",
    arguments: FreshIndexMock.allCases
  )
  func missingFreshIndex(mock: FreshIndexMock) async {
    let environment = mock.environment.merging([
      "BYLAWS_CORRECTION_ACTIVE": "1",
    ]) { _, value in value }

    await #expect(throws: IndexStoreError.unreadablePath(
      path: "/virtual/App",
      reason: "correction needs a fresh compiler index for '/virtual/App'; use the SwiftPM package built by this run"
    )) {
      try await ProjectIndexCache.correctionIndexStore(
        forRoot: "/virtual/App", environment: environment
      )
    }
  }

  @Test("Source-only rejects queries before calling builder")
  func sourceOnly() async {
    await ProjectIndexCache.$indexStoreBuilder.withValue(.init { _ in
      throw BuilderError()
    }) {
      await #expect(throws: IndexStoreError.unreadablePath(
        path: "/virtual/App",
        reason: "compiler-index queries cannot run with --source-only"
      )) {
        try await ProjectIndexCache.correctionIndexStore(
          forRoot: "/virtual/App",
          environment: ["BYLAWS_SOURCE_ONLY": "1"]
        )
      }
    }
  }

  @Test("Builder takes precedence and remains scoped")
  func scopedBuilder() async throws {
    let path = try await ProjectIndexCache.$indexStoreBuilder
      .withValue(.init { root in
        #expect(root == "/virtual/App")
        return "/virtual/builder/index/store"
      }) {
        try await ProjectIndexCache.correctionIndexStore(
          forRoot: "/virtual/App",
          environment: ["BYLAWS_CORRECTION_ACTIVE": "1"]
        )
      }
    let afterScope = try await ProjectIndexCache.correctionIndexStore(
      forRoot: "/virtual/App", environment: [:]
    )

    #expect(path == "/virtual/builder/index/store")
    #expect(afterScope == nil)
  }

  @Test("Cache reports builder failure before reading store")
  func builderFailure() async throws {
    let project = try TemporaryProject(files: [:])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    let root = try codebase.resolvedRootPath()
    let cache = ProjectIndexCache()

    await ProjectIndexCache.$indexStoreBuilder.withValue(.init { _ in
      throw BuilderError()
    }) {
      await #expect(throws: ProjectIndexError.indexUnavailable(.unreadablePath(
        path: root, reason: "the mock compiler failed"
      ))) {
        try await cache.index(for: codebase, modules: nil, unitOutputFiles: nil)
      }
    }

    #expect(await cache.readCount == 0)
  }

  @Test("Caught compiler failure prevents correction validation")
  func caughtBuilderFailure() async throws {
    let project = try TemporaryProject(files: [:])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()

    await SourceCapture.$collector.withValue(collector) {
      await ProjectIndexCache.$indexStoreBuilder.withValue(.init { _ in
        throw BuilderError()
      }) {
        _ = try? await codebase.projectIndex()
      }
    }
    let records = await collector.captured

    try #require(!records.isEmpty)
    #expect(records.contains {
      $0.unavailableReason?.contains("the mock compiler failed") == true
    })
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test(
    "Caught missing store prevents correction validation",
    .enabled(
      if: IndexStoreLocation.toolchainLibraryPath() != nil,
      "The active toolchain supplies no index library."
    )
  )
  func caughtStoreFailure() async throws {
    let project = try TemporaryProject(files: ["not-a-directory": ""])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    let store = project.fileURL(for: "not-a-directory/missing/index/store").path
    let collector = SourceCapture.Collector()

    await SourceCapture.$collector.withValue(collector) {
      await ProjectIndexCache.$indexStoreBuilder
        .withValue(.init { _ in store }) {
          _ = try? await codebase.projectIndex()
        }
    }
    let records = await collector.captured

    try #require(!records.isEmpty)
    #expect(records.contains {
      $0.unavailableReason?.contains(store) == true
    })
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  enum FreshIndexMock: CaseIterable, Sendable {
    case missingRootAndStore
    case missingStore
    case missingRoot
    case mismatchedRoot

    var environment: [String: String] {
      switch self {
      case .missingRootAndStore: [:]
      case .missingStore: ["BYLAWS_FRESH_INDEX_ROOT": "/virtual/App"]
      case .missingRoot:
        ["BYLAWS_FRESH_INDEX_STORE": "/virtual/build/index/store"]
      case .mismatchedRoot:
        [
          "BYLAWS_FRESH_INDEX_ROOT": "/virtual/Other",
          "BYLAWS_FRESH_INDEX_STORE": "/virtual/build/index/store",
        ]
      }
    }
  }

  private struct BuilderError: Error, CustomStringConvertible {
    var description: String { "the mock compiler failed" }
  }
}
