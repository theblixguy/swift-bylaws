import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Source query capture")
struct SourceQueryCaptureTests {
  @Test("Bazel query captures JSON outside source selection")
  func bazelExport() async throws {
    let project = try TemporaryProject(files: [
      "graph.json": BazelGraphMock.json,
      "Sources/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()
    let graph = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.bazelGraph(from: "graph.json")
    }
    #expect(graph.targets.count == 7)
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try project.write(#"{"results": []}"#, to: "graph.json")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test(
    "Folder layout captures empty directory changes outside source selection"
  )
  func folderInventory() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/Views/readme.txt": "",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Nothing/**"], excluding: ["Sources/**"],
      swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()
    let layout = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.checkFolderLayout(
        matching: "Sources/App", containing: ["Views"]
      )
    }
    #expect(layout.matchedFolders == ["Sources/App"])
    #expect(layout.missingFolders.isEmpty)
    #expect(layout.unexpectedFolders.isEmpty)
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try FileManager.default.createDirectory(
      at: project.fileURL(for: "Sources/App/Extra"),
      withIntermediateDirectories: true
    )

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test(
    "Explicit language mode captures excluded manifest",
    arguments: [false, true]
  )
  func manifestQuery(warmCache: Bool) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": Self.manifest(named: "Before"),
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      excluding: ["Package.swift"], swiftLanguageMode: .v6,
      parseCache: .init(budget: 0)
    )
    if warmCache {
      let previousCollector = SourceCapture.Collector()
      let previous = try await SourceCapture.$collector
        .withValue(previousCollector) {
          try await codebase.packageManifest
        }
      #expect(previous.name == "Before")
      let previousRecords = await previousCollector.captured
      try #require(!previousRecords.isEmpty)
      try await SourceCapture.validate(previousRecords)
    }
    let collector = SourceCapture.Collector()
    let manifest = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.packageManifest
    }
    #expect(manifest.name == "Before")
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try project.write(Self.manifest(named: "After"), to: "Package.swift")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test("Automatic roots capture new nearer project marker")
  func automaticRootMarker() async throws {
    let project = try TemporaryProject(files: [
      "MODULE.bazel": "",
      "Nested/App.swift": "struct App {}",
      "Nested/Rules/Bylaws.swift": "",
    ])
    let codebase = Codebase(
      root: .automatic(above: project.fileURL(for: "Nested/Rules/Bylaws.swift")
        .path),
      including: ["Nested/App.swift"], swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()
    let names = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.structs.map(\.name)
    }
    #expect(names == ["App"])
    #expect(try codebase.resolvedRootPath() == project.rootURL.path)
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try project.write("", to: "Nested/MODULE.bazel")

    #expect(try codebase.resolvedRootPath() == project.fileURL(for: "Nested")
      .path)
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test(
    "Parsed queries capture source contents on cache hits",
    arguments: [false, true]
  )
  func parsedSources(warmCache: Bool) async throws {
    let project = try TemporaryProject(files: [
      "Sources/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      swiftLanguageMode: .v6, parseCache: .init(budget: 0)
    )
    if warmCache {
      #expect(try await codebase.structs.map(\.name) == ["App"])
    }
    let collector = SourceCapture.Collector()
    let names = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.structs.map(\.name)
    }
    #expect(names == ["App"])
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try project.write("struct Changed {}", to: "Sources/App.swift")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test("Warm parse cache cannot validate omitted selected file")
  func addedSourceAfterCache() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      swiftLanguageMode: .v6, parseCache: .init(budget: 0)
    )
    #expect(try await codebase.structs.map(\.name) == ["App"])
    try project.write("struct Added {}", to: "Sources/Added.swift")
    let collector = SourceCapture.Collector()
    let names: [String]
    do {
      names = try await SourceCapture.$collector.withValue(collector) {
        try await codebase.structs.map(\.name).sorted()
      }
    } catch let error as CodebaseError {
      guard case .unreadable = error else { throw error }
      return
    }
    let records = await collector.captured
    try #require(!records.isEmpty)
    do {
      try await SourceCapture.validate(records)
    } catch is CaptureError {
      return
    }
    #expect(names == ["Added", "App"])
  }

  @Test("Warm package analysis cannot validate changed excluded manifest")
  func changedManifestAfterCache() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": Self.manifest(named: "Before"),
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      excluding: ["Package.swift"], swiftLanguageMode: .v6,
      parseCache: .init(budget: 0)
    )
    #expect(try await codebase.packageManifest.name == "Before")
    try project.write(Self.manifest(named: "After"), to: "Package.swift")
    let collector = SourceCapture.Collector()
    let name: String?
    do {
      name = try await SourceCapture.$collector.withValue(collector) {
        try await codebase.packageManifest.name
      }
    } catch let error as CodebaseError {
      guard case .unreadable = error else { throw error }
      return
    }
    let records = await collector.captured
    try #require(!records.isEmpty)
    do {
      try await SourceCapture.validate(records)
    } catch is CaptureError {
      return
    }
    #expect(name == "After")
  }

  @Test(
    "Restored project metadata cannot validate cached language mode",
    arguments: [
      Codebase.LanguageMode.automatic(.swiftPM), .automatic(.xcode),
    ]
  )
  func restoredMetadata(languageMode: Codebase.LanguageMode) async throws {
    let path: String
    let original: String
    let cached: String
    switch languageMode {
    case .automatic(.swiftPM):
      path = "Package.swift"
      original = Self.manifest(named: "App", mode: "6")
      cached = Self.manifest(named: "App", mode: "5")
    case .automatic(.xcode):
      path = "App.xcodeproj/project.pbxproj"
      original = xcodeProjectSource(targetSettings: "SWIFT_VERSION = 6.0;")
      cached = xcodeProjectSource(targetSettings: "SWIFT_VERSION = 5.0;")
    default:
      Issue.record("Language mode must select SwiftPM or Xcode")
      return
    }
    let project = try TemporaryProject(files: [
      path: original, "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      swiftLanguageMode: languageMode, parseCache: .init(budget: 0)
    )
    try project.write(cached, to: path)
    #expect(try await codebase.files.map(\.swiftLanguageMode) == [.v5])
    let unchangedCollector = SourceCapture.Collector()
    let unchangedModes = try await SourceCapture.$collector.withValue(
      unchangedCollector
    ) {
      try await codebase.files.map(\.swiftLanguageMode)
    }
    #expect(unchangedModes == [.v5])
    let unchangedRecords = await unchangedCollector.captured
    try #require(!unchangedRecords.isEmpty)
    try await SourceCapture.validate(unchangedRecords)

    try project.write(original, to: path)
    let collector = SourceCapture.Collector()
    let modes: [SwiftLanguageMode]
    do {
      modes = try await SourceCapture.$collector.withValue(collector) {
        try await codebase.files.map(\.swiftLanguageMode)
      }
    } catch let error as CodebaseError {
      guard case .unreadable = error else { throw error }
      return
    }
    let records = await collector.captured
    try #require(!records.isEmpty)
    do {
      try await SourceCapture.validate(records)
    } catch is CaptureError {
      return
    }
    #expect(modes == [.v6])
  }

  @Test("Concurrent callers capture cached package inputs independently")
  func concurrentManifestCallers() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": Self.manifest(named: "Before"),
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      excluding: ["Package.swift"], swiftLanguageMode: .v6,
      parseCache: .init(budget: 0)
    )
    #expect(try await codebase.packageManifest.name == "Before")
    let firstCollector = SourceCapture.Collector()
    let secondCollector = SourceCapture.Collector()
    async let first = SourceCapture.$collector.withValue(firstCollector) {
      try await codebase.packageManifest.name
    }
    async let second = SourceCapture.$collector.withValue(secondCollector) {
      try await codebase.packageManifest.name
    }
    let (firstName, secondName) = try await (first, second)
    #expect(firstName == "Before")
    #expect(secondName == "Before")
    let firstRecords = await firstCollector.captured
    let secondRecords = await secondCollector.captured
    try #require(!firstRecords.isEmpty)
    try #require(!secondRecords.isEmpty)
    try await SourceCapture.validate(firstRecords)
    try await SourceCapture.validate(secondRecords)

    try project.write(Self.manifest(named: "After"), to: "Package.swift")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(firstRecords)
    }
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(secondRecords)
    }
  }

  @Test(
    "Caught manifest failures prevent correction capture",
    arguments: [false, true]
  )
  func caughtManifestFailure(warmCache: Bool) async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "let package = Package(",
      "Sources/App/App.swift": "struct App {}",
    ])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      excluding: ["Package.swift"], swiftLanguageMode: .v6,
      parseCache: .init(budget: 0)
    )
    if warmCache {
      let previous = try? await codebase.packageManifest
      #expect(previous == nil)
    }
    let collector = SourceCapture.Collector()
    let manifest = await SourceCapture.$collector.withValue(collector) {
      try? await codebase.packageManifest
    }
    #expect(manifest == nil)
    let records = await collector.captured
    try #require(!records.isEmpty)
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test("Bazel capture rejects deleted root with unchanged external export")
  func deletedBazelRoot() async throws {
    let project = try TemporaryProject(files: [:])
    let external =
      try TemporaryProject(files: ["graph.json": BazelGraphMock.json])
    let export = external.fileURL(for: "graph.json")
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()
    let graph = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.bazelGraph(from: export.path)
    }
    #expect(graph.targets.count == 7)
    let records = await collector.captured
    try #require(!records.isEmpty)
    try await SourceCapture.validate(records)

    try FileManager.default.removeItem(at: project.rootURL)

    #expect(FileManager.default.fileExists(atPath: export.path))
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  @Test("Caught Bazel root failure prevents correction capture")
  func caughtBazelRootFailure() async throws {
    let project = try TemporaryProject(files: [:])
    let external =
      try TemporaryProject(files: ["graph.json": BazelGraphMock.json])
    let export = external.fileURL(for: "graph.json")
    let codebase = Codebase(
      root: .directory(project.rootURL.path), swiftLanguageMode: .v6
    )
    #expect(try await codebase.bazelGraph(from: export.path).targets.count == 7)
    try FileManager.default.removeItem(at: project.rootURL)
    let collector = SourceCapture.Collector()
    let graph = await SourceCapture.$collector.withValue(collector) {
      try? await codebase.bazelGraph(from: export.path)
    }
    #expect(graph == nil)
    #expect(FileManager.default.fileExists(atPath: export.path))
    let records = await collector.captured
    try #require(!records.isEmpty)
    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate(records)
    }
  }

  private static func manifest(
    named name: String,
    mode: String = "6"
  ) -> String {
    """
    // swift-tools-version: 6.0
    let package = Package(
      name: "\(name)", targets: [.target(name: "App")],
      swiftLanguageModes: [.v\(mode)]
    )
    """
  }
}
