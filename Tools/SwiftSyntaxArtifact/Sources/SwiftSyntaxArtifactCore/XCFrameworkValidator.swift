import Foundation

package struct XCFrameworkValidator {
  private let fileManager = FileManager.default
  private let processRunner = ProcessRunner()
  private let layout = ArtifactLayout()

  package init() {}

  package func validateSwiftArtifact(
    _ artifact: URL,
    modules: [String]
  ) throws {
    let metadata = try XCFrameworkMetadata.load(from: artifact)
    for library in metadata.availableLibraries {
      let directory = artifact.appendingPathComponent(
        library.libraryIdentifier
      )
      for module in modules {
        try validateSwiftModule(
          directory.appendingPathComponent("\(module).swiftmodule"),
          architectures: library.supportedArchitectures
        )
      }
      try validateSwiftSymbols(
        in: directory.appendingPathComponent(library.binaryPath)
      )
    }
  }

  package func validateCArtifact(_ artifact: URL) throws {
    let metadata = try XCFrameworkMetadata.load(from: artifact)
    for library in metadata.availableLibraries {
      let directory = artifact.appendingPathComponent(
        library.libraryIdentifier
      )
      let framework = directory.appendingPathComponent(library.libraryPath)
      let moduleMap = framework.appendingPathComponent(
        "Modules/module.modulemap"
      )
      let contents = try read(moduleMap, description: "C module map")
      guard contents.contains("framework module \(layout.cModule)") else {
        throw ArtifactError(
          "C module map must declare framework module \(layout.cModule) at \(moduleMap.path)."
        )
      }

      let header = framework.appendingPathComponent(
        "Headers/\(layout.cModule).h"
      )
      guard fileManager.fileExists(atPath: header.path) else {
        throw ArtifactError(
          "C framework must contain an umbrella header at \(header.path)."
        )
      }

      try validateCSymbols(
        in: directory.appendingPathComponent(library.binaryPath)
      )
    }
  }

  private func validateSwiftModule(
    _ module: URL,
    architectures: [String]
  ) throws {
    let files: [URL]
    do {
      files = try fileManager.contentsOfDirectory(
        at: module,
        includingPropertiesForKeys: nil
      )
    } catch {
      throw ArtifactError(
        "Cannot read Swift module at \(module.path): \(error.localizedDescription)"
      )
    }

    if files.contains(where: { $0.pathExtension == "swiftinterface" }) {
      throw ArtifactError(
        "Swift module must not contain a library-evolution interface at \(module.path)."
      )
    }
    for architecture in architectures where !files.contains(where: {
      $0.pathExtension == "swiftmodule"
        && $0.lastPathComponent.hasPrefix("\(architecture)-")
    }) {
      throw ArtifactError(
        "Swift module must contain an \(architecture) binary at \(module.path)."
      )
    }
  }

  private func validateCSymbols(in library: URL) throws {
    let symbols = try symbols(in: library)
    guard symbols.contains(where: {
      $0.isDefined && $0.name.contains(layout.privateCSymbolPrefix)
    }) else {
      throw ArtifactError(
        "C archive must define private SwiftSyntax symbols at \(library.path)."
      )
    }
    guard !symbols.contains(where: {
      $0.name.hasPrefix("swiftsyntax_")
        || $0.name.hasPrefix("_swiftsyntax_")
    }) else {
      throw ArtifactError(
        "C archive must not contain an original SwiftSyntax symbol at \(library.path)."
      )
    }
  }

  private func validateSwiftSymbols(in library: URL) throws {
    let symbols = try symbols(in: library)
    guard !symbols.contains(where: {
      $0.isDefined && $0.name.contains(layout.privateCSymbolPrefix)
    }) else {
      throw ArtifactError(
        "Swift archive must not define C shim symbols at \(library.path)."
      )
    }
    guard !symbols.contains(where: {
      $0.name.hasPrefix("swiftsyntax_")
        || $0.name.hasPrefix("_swiftsyntax_")
    }) else {
      throw ArtifactError(
        "Swift archive must not contain an original SwiftSyntax symbol at \(library.path)."
      )
    }
  }

  private func symbols(in library: URL) throws -> [Symbol] {
    let output = try processRunner.output(
      "/usr/bin/nm",
      arguments: ["-g", library.path]
    )
    return output.split(separator: "\n").compactMap { line in
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.count >= 2 else { return nil }
      return Symbol(
        type: String(fields[fields.count - 2]),
        name: String(fields[fields.count - 1])
      )
    }
  }

  private func read(_ url: URL, description: String) throws -> String {
    do {
      return try String(contentsOf: url, encoding: .utf8)
    } catch {
      throw ArtifactError(
        "Cannot read \(description) at \(url.path): \(error.localizedDescription)"
      )
    }
  }

  private struct Symbol {
    let type: String
    let name: String

    var isDefined: Bool {
      type != "U" && type != "u"
    }
  }
}
