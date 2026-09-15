package import BylawsPaths

package enum IndexStoreCandidates {
  package static let buildConfigurations = ["debug", "release"]
  package static let derivedDataStoreNames = [
    "Index.noindex/DataStore", "Index/DataStore",
  ]
  // Xcode build directories are at most six levels below Derived Data.
  package static let maximumDerivedDataSearchDepth = 6
  // The editor's separate build does not belong to the running build.
  package static let editorBuildDirectoryName = "index-build"

  package static func xcodeBuildDirectories(
    in environment: [String: String]
  ) -> [String] {
    [
      "BUILT_PRODUCTS_DIR",
      "BUILD_DIR",
      "OBJROOT",
      "SYMROOT",
      "PROJECT_TEMP_DIR",
      "TARGET_TEMP_DIR",
      "CONFIGURATION_BUILD_DIR",
    ].compactMap { environment[$0] }
  }

  package static func derivedDataStores(
    above anchor: LexicalFilePath
  ) -> [LexicalFilePath] {
    var candidates: [LexicalFilePath] = []
    var directory = anchor
    for _ in 0..<maximumDerivedDataSearchDepth {
      for name in derivedDataStoreNames {
        candidates.append(directory.appending(name))
      }
      let parent = directory.removingLastComponent()
      if parent == directory { break }
      directory = parent
    }
    return candidates
  }

  package static func packageStores(
    inBuildDirectory build: LexicalFilePath,
    entries: [String]
  ) -> [LexicalFilePath] {
    let direct = buildConfigurations.map {
      build.appending($0 + "/index/store")
    }
    let nested = entries.sorted()
      .filter { $0 != editorBuildDirectoryName }
      .flatMap { entry in
        buildConfigurations.map {
          build.appending(entry).appending($0 + "/index/store")
        }
      }
    return [build.appending("out")] + direct + nested
  }

  package static func runningBuildStore(
    besideExecutableAt executable: LexicalFilePath
  ) -> LexicalFilePath? {
    guard !executable.contains(component: editorBuildDirectoryName)
    else { return nil }
    var directory = executable.removingLastComponent()
    while let name = directory.lastComponent {
      let parent = directory.removingLastComponent()
      if parent.lastComponent == "Products" {
        let output = parent.removingLastComponent()
        if output.lastComponent == "out" { return output }
      }
      if buildConfigurations.contains(name) {
        return directory.appending("index/store")
      }
      directory = parent
    }
    return nil
  }
}
