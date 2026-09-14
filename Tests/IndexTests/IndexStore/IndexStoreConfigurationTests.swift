import BylawsIndexStore
import Foundation
import Testing

@Suite(
  "Index store configurations",
  .enabled(
    if: ToolchainPaths.activeCompilerPath() != nil
      && IndexStoreLocation.toolchainLibraryPath() != nil,
    "The active toolchain supplies no compiler or index library."
  ),
  .tags(.indexStore)
)
struct IndexStoreConfigurationTests {
  private let compiler: URL

  init() throws {
    compiler = URL(
      fileURLWithPath: try #require(ToolchainPaths.activeCompilerPath())
    )
  }

  @Test("Temporary project removes directory at scope exit")
  func scopedCleanup() throws {
    let root: URL
    do {
      let project = try IndexStoreTestProject(compiler: compiler)
      root = project.root
      try #require(FileManager.default.fileExists(atPath: project.source.path))
    }

    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  @Test("Thrown error removes temporary project")
  func throwingCleanup() throws {
    var root: URL?
    #expect(throws: MockError.self) {
      let project = try IndexStoreTestProject(compiler: compiler)
      root = project.root
      throw MockError()
    }

    let path = try #require(root).path
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  private struct MockError: Error {}

  @Test("A mixed store requires an exact build selection")
  func rejectsMixedBuildConfigurations() throws {
    let project = try IndexStoreTestProject(compiler: compiler)
    let outputIdentities = try project.compileBothConfigurations()

    let store = try IndexStore(path: project.store.path)
    let units = try store.unitNames().map(store.unit(named:))
    let sourceUnits = units.filter {
      $0.moduleName == project.module && $0.mainFile == project.source.path
    }
    #expect(sourceUnits.count == 2)
    #expect(Set(sourceUnits.map(\.outputFile)).count == 2)
    #expect(
      Set(sourceUnits.map(\.outputFile))
        == [outputIdentities.debug, outputIdentities.release]
    )

    do {
      _ = try ProjectIndex(store: store, modules: [project.module])
      Issue.record("The index combined two build configurations.")
    } catch {
      guard case let .mixedBuildConfigurations(
        module,
        file,
        outputFiles
      ) = error else {
        Issue.record("The index reported the wrong error: \(error)")
        return
      }
      #expect(module == project.module)
      #expect(file == project.source.path)
      #expect(outputFiles == Set(sourceUnits.map(\.outputFile)))
    }

    let debugUnit = try #require(
      sourceUnits.first { $0.outputFile == outputIdentities.debug }
    )
    let debugIndex = try ProjectIndex(
      store: store,
      modules: [project.module],
      unitOutputFiles: [debugUnit.outputFile]
    )
    #expect(!debugIndex.definitions(of: "DebugOnly").isEmpty)
    #expect(debugIndex.definitions(of: "ReleaseOnly").isEmpty)

    do {
      _ = try ProjectIndex(
        store: store,
        unitOutputFiles: ["missing-output"]
      )
      Issue.record("The index accepted a missing output identity.")
    } catch {
      guard case let .missingUnitOutputFiles(outputFiles) = error else {
        Issue.record("The index reported the wrong error: \(error)")
        return
      }
      #expect(outputFiles == ["missing-output"])
    }
  }

  @Test("An exact selection skips a deleted source")
  func skipsASelectedDeletedSource() throws {
    let project = try IndexStoreTestProject(compiler: compiler)
    let outputIdentities = try project.compileBothConfigurations()
    try FileManager.default.removeItem(at: project.source)

    let store = try IndexStore(path: project.store.path)
    let index = try ProjectIndex(
      store: store,
      unitOutputFiles: [outputIdentities.debug]
    )

    #expect(index.modules.isEmpty)
    #expect(index.fileCount == 0)
    #expect(index.definitions(of: "DebugOnly").isEmpty)
  }

  @Test("A normal build takes precedence over its plugin tool build")
  func prefersTheNormalBuildOverAPluginTool() throws {
    let project = try IndexStoreTestProject(compiler: compiler)
    let outputIdentities = try project.compileNormalAndPluginTool()
    let store = try IndexStore(path: project.store.path)

    let inferred = try ProjectIndex(
      store: store,
      modules: [project.module]
    )
    #expect(!inferred.definitions(of: "DebugOnly").isEmpty)
    #expect(inferred.definitions(of: "ReleaseOnly").isEmpty)

    let selectedTool = try ProjectIndex(
      store: store,
      modules: [project.module],
      unitOutputFiles: [outputIdentities.pluginTool]
    )
    #expect(selectedTool.definitions(of: "DebugOnly").isEmpty)
    #expect(!selectedTool.definitions(of: "ReleaseOnly").isEmpty)
  }
}

private struct IndexStoreTestProject: ~Copyable {
  let module = "MixedConfiguration"
  let compiler: URL
  let root: URL
  let source: URL
  let store: URL

  init(compiler: URL) throws {
    self.compiler = compiler
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bylaws-index-config-\(UUID().uuidString)")
    source = root.appendingPathComponent("Shared.swift")
    store = root.appendingPathComponent("store")

    let manager = FileManager.default
    for directory in ["debug", "release", "module-cache", "store"] {
      try manager.createDirectory(
        at: root.appendingPathComponent(directory),
        withIntermediateDirectories: true
      )
    }
    try """
    #if DEBUG
    struct DebugOnly {}
    #else
    struct ReleaseOnly {}
    #endif
    """.write(to: source, atomically: true, encoding: .utf8)
  }

  func compileBothConfigurations() throws -> (debug: String, release: String) {
    let debug = try compile(configuration: "debug", arguments: ["-DDEBUG"])
    let release = try compile(configuration: "release", arguments: [])
    return (debug, release)
  }

  func compileNormalAndPluginTool() throws -> (
    normal: String,
    pluginTool: String
  ) {
    let normal = try compile(
      configuration: "debug",
      arguments: ["-DDEBUG"]
    )
    let pluginTool = try compile(
      configuration: "plugin",
      arguments: [],
      outputIdentity: "/__bylaws_index_tests__/"
        + "\(module)-tool.build/Shared.swift.o"
    )
    return (normal, pluginTool)
  }

  deinit {
    try? FileManager.default.removeItem(at: root)
  }

  private func compile(
    configuration: String,
    arguments: [String],
    outputIdentity: String? = nil
  ) throws -> String {
    let output = root
      .appendingPathComponent(configuration)
      .appendingPathComponent("Shared.swift.o")
    let outputIdentity = outputIdentity
      ?? "/__bylaws_index_tests__/\(configuration)"
    try run(
      [
        "-c", source.path,
        "-module-name", module,
        "-module-cache-path", root.appendingPathComponent("module-cache").path,
        "-index-store-path", store.path,
        "-index-unit-output-path", outputIdentity,
        "-o", output.path,
      ] + arguments,
      at: root
    )
    return outputIdentity
  }

  private func run(_ arguments: [String], at directory: URL) throws {
    let process = Process()
    process.executableURL = compiler
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let errors = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    try process.run()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CompilerError.failed(
        status: process.terminationStatus,
        output: String(decoding: errorData, as: UTF8.self)
      )
    }
  }

  private enum CompilerError: Error {
    case failed(status: Int32, output: String)
  }
}
