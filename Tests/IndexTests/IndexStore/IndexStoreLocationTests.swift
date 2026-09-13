import BylawsIndexStore
import BylawsPaths
import Foundation
import Testing

@Suite("Index store discovery", .tags(.indexStore))
struct IndexStoreLocationTests {
  @Test(
    "An environment variable selects the index store before discovery",
    arguments: [IndexStoreLocation.environmentKey, "INDEX_DATA_STORE_DIR"]
  )
  func usesTheEnvironmentVariableFirst(key: String) throws {
    let derived = try DerivedData()
    defer { derived.remove() }
    let found = try IndexStoreLocation.path(
      forPackageContaining: "/nowhere/Tests/File.swift",
      environment: [key: derived.store]
    )
    #expect(found == derived.store)
  }

  @Test("An invalid explicit store is an error")
  func invalidExplicitStoreFails() throws {
    let derived = try DerivedData()
    defer { derived.remove() }
    #expect(
      throws: IndexStoreError.missingStore(searched: ["/invalid/store"])
    ) {
      try IndexStoreLocation.path(
        forPackageContaining: "/nowhere/Tests/File.swift",
        environment: [
          IndexStoreLocation.environmentKey: "/invalid/store",
          "INDEX_DATA_STORE_DIR": derived.store,
        ]
      )
    }
  }

  @Test(
    "Unreadable index store error includes its path",
    .enabled(if: getuid() != 0, "Root can read a directory with mode 000.")
  )
  func unreadableExplicitStoreFails() throws {
    let path = NSTemporaryDirectory()
      + "bylaws-unreadable-store-\(UUID().uuidString)"
    try FileManager.default.createDirectory(
      atPath: path + "/v5",
      withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: path
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: path
      )
      try? FileManager.default.removeItem(atPath: path)
    }

    #expect {
      try IndexStoreLocation.path(
        forPackageContaining: "/nowhere/Tests/File.swift",
        environment: [IndexStoreLocation.environmentKey: path]
      )
    } throws: { error in
      guard case let IndexStoreError.unreadablePath(errorPath, _) = error
      else { return false }
      return errorPath == path
    }
  }

  @Test(
    "Each Xcode build path finds the adjacent index store",
    arguments: [
      "BUILT_PRODUCTS_DIR", "BUILD_DIR", "OBJROOT", "SYMROOT",
      "PROJECT_TEMP_DIR", "TARGET_TEMP_DIR", "CONFIGURATION_BUILD_DIR",
    ]
  )
  func findsAStoreFromABuildDirectory(key: String) throws {
    let derived = try DerivedData()
    defer { derived.remove() }
    let deep = derived.path + "/Build/Intermediates.noindex/Extra/Deeper"
    let found = try IndexStoreLocation.path(
      forPackageContaining: "/nowhere/Tests/File.swift",
      environment: [key: deep]
    )
    #expect(found == derived.store)
  }

  @Test("The search finds the older name for the index directory")
  func findsTheOlderIndexDirectory() throws {
    let older = NSTemporaryDirectory() + "bylaws-old-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: older) }
    try FileManager.default.createDirectory(
      atPath: older + "/Index/DataStore/v5",
      withIntermediateDirectories: true
    )
    let found = try IndexStoreLocation.path(
      forPackageContaining: "/nowhere/Tests/File.swift",
      environment: ["BUILT_PRODUCTS_DIR": older + "/Build/Products/Debug"]
    )
    #expect(found == older + "/Index/DataStore")
  }

  @Test("Package discovery ignores the editor's index store")
  func ignoresTheEditorStore() throws {
    let package = NSTemporaryDirectory() + "bylaws-package-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: package) }
    for entry in ["index-build", "arm64-apple-macosx"] {
      try FileManager.default.createDirectory(
        atPath: package + "/.build/\(entry)/debug/index/store/v5",
        withIntermediateDirectories: true
      )
    }
    let found = try IndexStoreLocation.path(
      forPackageAt: package,
      environment: [:]
    )
    #expect(found == package + "/.build/arm64-apple-macosx/debug/index/store")
  }

  @Test("Package discovery ignores a file in the build directory")
  func ignoresAFileInTheBuildDirectory() throws {
    let package = NSTemporaryDirectory() + "bylaws-lock-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: package) }
    let store = package + "/.build/arm64-apple-macosx/debug/index/store"
    try FileManager.default.createDirectory(
      atPath: store + "/v5",
      withIntermediateDirectories: true
    )
    try #require(
      FileManager.default.createFile(
        atPath: package + "/.build/.lock",
        contents: nil
      )
    )

    let found = try IndexStoreLocation.path(
      forPackageAt: package,
      environment: [:]
    )
    #expect(found == store)
  }

  @Test("Package discovery finds a release index store")
  func findsAReleaseStore() throws {
    let package = NSTemporaryDirectory() + "bylaws-release-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: package) }
    let release = package + "/.build/arm64-apple-macosx/release/index/store"
    try FileManager.default.createDirectory(
      atPath: release + "/v5",
      withIntermediateDirectories: true
    )

    let found = try IndexStoreLocation.path(
      forPackageAt: package,
      environment: [:]
    )
    #expect(found == release)
  }

  @Test("Package discovery selects the newest supported store version")
  func newestStoreVersionWins() throws {
    let package = NSTemporaryDirectory() + "bylaws-versions-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: package) }
    let debug = package + "/.build/debug/index/store"
    let release = package + "/.build/release/index/store"
    try FileManager.default.createDirectory(
      atPath: debug + "/v6/units",
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      atPath: release + "/v5/units",
      withIntermediateDirectories: true
    )
    let now = Date()
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(60)],
      ofItemAtPath: debug + "/v6/units"
    )
    try FileManager.default.setAttributes(
      [.modificationDate: now],
      ofItemAtPath: release + "/v5/units"
    )

    let found = try IndexStoreLocation.forPackage(
      at: LexicalFilePath(package),
      executablePath: nil,
      workingDirectory: LexicalFilePath("/")
    )

    #expect(found == debug)
  }

  @Test("A SwiftPM executable path finds an index store in the scratch path")
  func findsAScratchPathStore() throws {
    let package = NSTemporaryDirectory() + "bylaws-source-\(UUID().uuidString)"
    let scratch = NSTemporaryDirectory() + "bylaws-scratch-\(UUID().uuidString)"
    defer {
      try? FileManager.default.removeItem(atPath: package)
      try? FileManager.default.removeItem(atPath: scratch)
    }
    let release = scratch + "/arm64-apple-macosx/release"
    try FileManager.default.createDirectory(
      atPath: release + "/index/store/v5",
      withIntermediateDirectories: true
    )

    let executable = release
      + "/BylawsPackageTests.xctest/Contents/MacOS/tests"
    let found = try IndexStoreLocation.forPackage(
      at: LexicalFilePath(package),
      executablePath: executable,
      workingDirectory: LexicalFilePath(package)
    )
    #expect(found == release + "/index/store")
  }

  @Test("A Linux toolchain layout finds libIndexStore")
  func findsTheLinuxToolchainLibrary() throws {
    let toolchain = NSTemporaryDirectory()
      + "bylaws-toolchain-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: toolchain) }
    let compiler = toolchain + "/usr/bin/swiftc"
    let library = toolchain + "/usr/lib/libIndexStore.so"
    try FileManager.default.createDirectory(
      atPath: toolchain + "/usr/bin",
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      atPath: toolchain + "/usr/lib",
      withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: compiler, contents: nil))
    #expect(FileManager.default.createFile(atPath: library, contents: nil))

    let found = ToolchainPaths.libraryPath(
      compilerPath: compiler,
      libraryName: "libIndexStore.so"
    )
    #expect(found == library)
  }

  @Test("A failed search reports every checked path")
  func reportsWhatItSearched() {
    #expect(
      throws: IndexStoreError.missingStore(
        searched: ["/nowhere/Tests/File.swift"]
      )
    ) {
      try IndexStoreLocation.path(
        forPackageContaining: "/nowhere/Tests/File.swift",
        environment: [:]
      )
    }
  }

  @Test(
    "A package file finds the package's index store",
    .enabled(
      if: IndexUnderTest.isAvailable,
      "This build wrote no index store. Build in debug first."
    )
  )
  func findsThePackageStore() throws {
    let path = try IndexStoreLocation.path(
      forPackageContaining: #filePath,
      environment: [:]
    )
    #expect(!path.contains("index-build"))
    let store = try IndexStore(path: path)
    #expect(!store.unitNames().isEmpty)
  }
}

private struct DerivedData {
  let path: String

  var store: String { path + "/Index.noindex/DataStore" }

  init() throws {
    path = NSTemporaryDirectory() + "bylaws-derived-\(UUID().uuidString)"
    try FileManager.default.createDirectory(
      atPath: store + "/v5",
      withIntermediateDirectories: true
    )
  }

  func remove() {
    try? FileManager.default.removeItem(atPath: path)
  }
}
