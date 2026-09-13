package import Foundation

package enum ExecutableLocator {
  package static func locate(
    named executableName: String,
    overriddenBy environmentVariable: String,
    relativeTo sourceFilePath: String
  ) throws -> URL {
    let environment = ProcessInfo.processInfo.environment
    let candidates: [URL]
    if let override = environment[environmentVariable] {
      candidates = [URL(fileURLWithPath: override)]
    } else {
      // Linux runs the tests as a flat executable, and Bundle.allBundles
      // crashes in swift-corelibs-foundation 6.2.
      #if canImport(Darwin)
        let testBundle = Bundle.allBundles.first {
          $0.bundleURL.pathExtension == "xctest"
        }
      #else
        let testBundle: Bundle? = nil
      #endif
      var sourceCandidates: [URL] = []
      var directory = URL(fileURLWithPath: sourceFilePath)
        .deletingLastPathComponent()
      for _ in 0..<8 {
        sourceCandidates.append(
          directory.appendingPathComponent(".build/debug/\(executableName)")
        )
        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path { break }
        directory = parent
      }
      candidates = [
        testBundle?.bundleURL.deletingLastPathComponent()
          .appendingPathComponent(executableName),
        Bundle.main.executableURL?.deletingLastPathComponent()
          .appendingPathComponent(executableName),
      ].compactMap(\.self) + sourceCandidates
    }

    if let executable = candidates.first(where: {
      FileManager.default.isExecutableFile(atPath: $0.path)
    }) {
      return executable
    }

    let paths = candidates.map(\.path).joined(separator: ", ")
    throw MissingTestExecutable(
      message: "Could not find \(executableName). Checked: \(paths). "
        + "Set \(environmentVariable) to the executable path."
    )
  }
}

package struct MissingTestExecutable: Error, CustomStringConvertible {
  package let message: String
  package var description: String { message }
}
