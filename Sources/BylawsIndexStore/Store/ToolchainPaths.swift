import BylawsPaths
import Foundation

package enum ToolchainPaths {
  package static func indexStoreLibraryPath() -> String? {
    guard let compiler = activeCompilerPath() else { return nil }
    return libraryPath(compilerPath: compiler, libraryName: libraryName)
  }

  package static func libraryPath(
    compilerPath: String,
    libraryName: String
  ) -> String? {
    let toolchain = LexicalFilePath(
      URL(fileURLWithPath: compilerPath).resolvingSymlinksInPath().path
    )
    .removingLastComponent()
    .removingLastComponent()
    let candidates = [
      toolchain.appending("lib/\(libraryName)"),
      toolchain.appending("lib/swift/host/\(libraryName)"),
      toolchain.appending("lib/swift/linux/\(libraryName)"),
    ]
    return candidates.first {
      FileManager.default.fileExists(atPath: $0.string)
    }?.string
  }

  private static var libraryName: String {
    #if canImport(Darwin)
      "libIndexStore.dylib"
    #else
      "libIndexStore.so"
    #endif
  }

  #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    package static func activeCompilerPath() -> String? {
      nil
    }
  #else
    package static func activeCompilerPath() -> String? {
      #if canImport(Darwin)
        standardOutput(
          ofExecutableAt: "/usr/bin/xcrun",
          arguments: ["--find", "swiftc"]
        )
      #elseif canImport(Glibc)
        swiftCompilerPath(in: ProcessInfo.processInfo.environment)
      #else
        nil
      #endif
    }

    private static func standardOutput(
      ofExecutableAt path: String,
      arguments: [String]
    ) -> String? {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      let output = Pipe()
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { return nil }
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
  #endif

  #if canImport(Glibc)
    private static func swiftCompilerPath(
      in environment: [String: String]
    ) -> String? {
      if let swiftExec = environment["SWIFT_EXEC"],
         let path = executablePath(named: swiftExec, environment: environment)
      {
        return path
      }
      return executablePath(named: "swiftc", environment: environment)
    }

    private static func executablePath(
      named name: String,
      environment: [String: String]
    ) -> String? {
      if name.contains("/") {
        return FileManager.default.isExecutableFile(atPath: name) ? name : nil
      }
      return (environment["PATH"] ?? "")
        .split(separator: ":")
        .map {
          LexicalFilePath(String($0)).appending(name).string
        }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
  #endif
}
