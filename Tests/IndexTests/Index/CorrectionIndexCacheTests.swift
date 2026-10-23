import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite(
  "Correction index cache",
  .enabled(
    if: ToolchainPaths.activeCompilerPath() != nil
      && IndexStoreLocation.toolchainLibraryPath() != nil,
    "The active toolchain supplies no compiler or index library."
  ),
  .tags(.indexStore)
)
struct CorrectionIndexCacheTests {
  @Test("Different stores under one root keep separate cached indexes")
  func separateStores() async throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let firstStore = try compile(
      "struct OriginalOnly {}", in: project, build: "first"
    )
    let secondStore = try compile(
      "struct ReplacementOnly {}", in: project, build: "second"
    )
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"], swiftLanguageMode: .v6
    )
    let cache = ProjectIndexCache()

    let first = try await index(at: firstStore, through: cache, for: codebase)
    let second = try await index(at: secondStore, through: cache, for: codebase)
    let firstAgain = try await index(
      at: firstStore,
      through: cache,
      for: codebase
    )

    #expect(!first.definitions(of: "OriginalOnly").isEmpty)
    #expect(first.definitions(of: "ReplacementOnly").isEmpty)
    #expect(second.definitions(of: "OriginalOnly").isEmpty)
    #expect(!second.definitions(of: "ReplacementOnly").isEmpty)
    #expect(!firstAgain.definitions(of: "OriginalOnly").isEmpty)
    #expect(firstAgain.definitions(of: "ReplacementOnly").isEmpty)
    #expect(await cache.readCount == 2)
  }

  private func index(
    at store: String, through cache: ProjectIndexCache, for codebase: Codebase
  ) async throws -> ProjectIndex {
    try await ProjectIndexCache.$indexStoreBuilder
      .withValue(.init { _ in store }) {
        try await cache.index(
          for: codebase, modules: ["CorrectionApp"], unitOutputFiles: nil
        )
      }
  }

  private func compile(
    _ source: String, in project: TemporaryProject, build: String
  ) throws -> String {
    try project.write(source, to: "Sources/App.swift")
    let buildDirectory = project.fileURL(for: "builds/\(build)")
    let store = buildDirectory.appendingPathComponent("index/store")
    try FileManager.default.createDirectory(
      at: store, withIntermediateDirectories: true
    )
    let process = Process()
    process.executableURL = URL(
      fileURLWithPath: try #require(ToolchainPaths.activeCompilerPath())
    )
    process.arguments = [
      "-c", "-module-name", "CorrectionApp",
      "-index-store-path", store.path,
      "-module-cache-path", project.fileURL(for: "module-cache").path,
      "-o", buildDirectory.appendingPathComponent("App.o").path,
      project.fileURL(for: "Sources/App.swift").path,
    ]
    process.currentDirectoryURL = project.rootURL
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    let output = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(
      process.terminationStatus == 0,
      "\(String(decoding: output, as: UTF8.self))"
    )
    return store.path
  }
}
