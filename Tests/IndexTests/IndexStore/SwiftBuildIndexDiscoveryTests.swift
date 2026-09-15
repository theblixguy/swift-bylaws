import BylawsIndexStore
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Swift Build index discovery", .tags(.indexStore))
struct SwiftBuildIndexDiscoveryTests {
  @Test("Package search finds Swift Build index")
  func packageStore() throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let store = project.rootURL.appending(path: ".build/out")
    try FileManager.default.createDirectory(
      at: store.appending(path: "v5"), withIntermediateDirectories: true
    )
    #expect(try IndexStoreLocation.path(
      forPackageAt: project.rootURL.path, environment: [:]
    ) == store.path)
  }

  @Test("Newest index wins across build systems", arguments: [true, false])
  func newestStore(swiftBuildIsNewer: Bool) throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let swiftBuild = project.rootURL.appending(path: ".build/out")
    let native = project.rootURL.appending(path: ".build/debug/index/store")
    for (store, timestamp) in [
      (swiftBuild, swiftBuildIsNewer ? 200.0 : 100.0),
      (native, swiftBuildIsNewer ? 100.0 : 200.0),
    ] {
      let units = store.appending(path: "v5/units")
      try FileManager.default.createDirectory(
        at: units, withIntermediateDirectories: true
      )
      try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: timestamp)],
        ofItemAtPath: units.path
      )
    }
    let found = try IndexStoreLocation.path(
      forPackageAt: project.rootURL.path, environment: [:]
    )
    #expect(found == (swiftBuildIsNewer ? swiftBuild : native).path)
  }

  @Test("Running Swift Build executable selects scratch index")
  func scratchStore() throws {
    let project = try TemporaryProject(files: ["Package.swift": ""])
    let store = project.rootURL.appending(path: "scratch/out")
    try FileManager.default.createDirectory(
      at: store.appending(path: "v5"), withIntermediateDirectories: true
    )
    #expect(try IndexStoreLocation.forPackage(
      at: LexicalFilePath(project.rootURL.path),
      executablePath: "scratch/out/Products/Debug/tool",
      workingDirectory: LexicalFilePath(project.rootURL.path)
    ) == store.path)
  }

  @Test("Build output without an index preserves native discovery")
  func missingSwiftBuildIndex() throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      ".build/out/Products/Debug/tool": "",
    ])
    let store = project.rootURL.appending(path: ".build/debug/index/store")
    try FileManager.default.createDirectory(
      at: store.appending(path: "v5"), withIntermediateDirectories: true
    )
    #expect(try IndexStoreLocation.path(
      forPackageAt: project.rootURL.path, environment: [:]
    ) == store.path)
  }
}
