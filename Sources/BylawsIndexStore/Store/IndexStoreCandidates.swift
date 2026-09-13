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
    return direct + nested
  }

  package static func runningBuildStore(
    besideExecutableAt executable: LexicalFilePath
  ) -> LexicalFilePath? {
    var directory = executable.removingLastComponent()
    for _ in 0..<10 {
      if let name = directory.lastComponent,
         buildConfigurations.contains(name)
      {
        let candidate = directory.appending("index/store")
        return candidate.contains(component: editorBuildDirectoryName)
          ? nil : candidate
      }
      let parent = directory.removingLastComponent()
      if parent == directory { break }
      directory = parent
    }
    return nil
  }
}
