import Foundation

package struct XCFrameworkCombiner {
  private let fileManager = FileManager.default
  private let processRunner = ProcessRunner()
  private let textRewriter = TextRewriter()
  private let layout = ArtifactLayout()

  package init() {}

  package func combine(
    frameworks: URL,
    sourcePackage: URL,
    output: URL
  ) throws {
    guard output.lastPathComponent == "\(layout.artifactName).xcframework"
    else {
      throw ArtifactError(
        "Output must be named \(layout.artifactName).xcframework."
      )
    }
    guard !fileManager.fileExists(atPath: output.path) else {
      throw ArtifactError("Output already exists at \(output.path).")
    }

    let work = output
      .deletingLastPathComponent()
      .appendingPathComponent(".\(output.lastPathComponent).\(UUID())")
    try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: work) }

    let artifactMetadata = try metadata(
      for: xcframework(
        named: layout.moduleName(for: "SwiftSyntax"),
        under: frameworks
      )
    )
    var stagedLibraries: [(identifier: String, url: URL)] = []
    for library in artifactMetadata.availableLibraries {
      let identifier = library.libraryIdentifier
      let stagedLibrary = work.appendingPathComponent(
        "\(identifier)/lib\(layout.artifactName).a"
      )
      try fileManager.createDirectory(
        at: stagedLibrary.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let modules = layout.swiftModules.map(\.name) + [layout.cModule]
      let inputLibraries = try modules.map {
        (
          module: $0,
          binary: try binary(
            module: $0,
            identifier: identifier,
            frameworks: frameworks
          )
        )
      }
      try combineLibraries(
        inputLibraries,
        architectures: library.supportedArchitectures,
        output: stagedLibrary,
        work: work.appendingPathComponent("objects/\(identifier)")
      )
      stagedLibraries.append((identifier, stagedLibrary))
    }

    let temporaryOutput = work.appendingPathComponent(
      "\(layout.artifactName).xcframework"
    )
    try processRunner.run(
      "/usr/bin/xcodebuild",
      arguments: ["-create-xcframework"] + stagedLibraries.flatMap {
        ["-library", $0.url.path]
      } + ["-output", temporaryOutput.path]
    )

    for (identifier, _) in stagedLibraries {
      for module in layout.swiftModules {
        let source = try swiftModule(
          module: module.name,
          identifier: identifier,
          frameworks: frameworks
        )
        let destination = temporaryOutput
          .appendingPathComponent(identifier)
          .appendingPathComponent("\(module.name).swiftmodule")
        try fileManager.copyItem(at: source, to: destination)
        try validateInterfaces(in: destination, moduleName: module.name)
      }
      try validateSymbols(
        in: temporaryOutput
          .appendingPathComponent(identifier)
          .appendingPathComponent("lib\(layout.artifactName).a")
      )
    }
    try copyLicence(from: sourcePackage, to: temporaryOutput)

    try fileManager.createDirectory(
      at: output.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.moveItem(at: temporaryOutput, to: output)
  }

  private func combineLibraries(
    _ libraries: [(module: String, binary: URL)],
    architectures: [String],
    output: URL,
    work: URL
  ) throws {
    guard !architectures.isEmpty else {
      throw ArtifactError("XCFramework library has no architectures.")
    }
    var architectureLibraries: [URL] = []
    for architecture in architectures {
      let architectureDirectory = work.appendingPathComponent(architecture)
      let objectDirectory = architectureDirectory
        .appendingPathComponent("combined")
      try fileManager.createDirectory(
        at: objectDirectory,
        withIntermediateDirectories: true
      )
      var objects: [URL] = []
      for library in libraries {
        let archive = architectureDirectory.appendingPathComponent(
          "\(library.module).a"
        )
        try extract(
          architecture: architecture,
          from: library.binary,
          to: archive
        )
        let members = try processRunner.output(
          "/usr/bin/ar",
          arguments: ["-t", archive.path]
        ).split(separator: "\n").map(String.init)
        guard Set(members).count == members.count else {
          throw ArtifactError(
            "Archive has duplicate members at \(library.binary.path)."
          )
        }
        let extracted = architectureDirectory
          .appendingPathComponent(library.module)
        try fileManager.createDirectory(
          at: extracted,
          withIntermediateDirectories: true
        )
        try processRunner.run(
          "/usr/bin/ar",
          arguments: ["-x", archive.path],
          currentDirectory: extracted
        )
        for (index, member) in members.enumerated() where
          !member.hasPrefix("__.SYMDEF")
        {
          let source = extracted.appendingPathComponent(member)
          let destination = objectDirectory.appendingPathComponent(
            "\(library.module)-\(index)-\(member)"
          )
          try fileManager.copyItem(at: source, to: destination)
          objects.append(destination)
        }
      }
      let architectureLibrary = architectureDirectory.appendingPathComponent(
        "lib\(layout.artifactName).a"
      )
      try processRunner.run(
        "/usr/bin/libtool",
        arguments: ["-static", "-o", architectureLibrary.path]
          + objects.map(\.path)
      )
      architectureLibraries.append(architectureLibrary)
    }
    try processRunner.run(
      "/usr/bin/lipo",
      arguments: ["-create"] + architectureLibraries.map(\.path)
        + ["-output", output.path]
    )
  }

  private func extract(
    architecture: String,
    from binary: URL,
    to output: URL
  ) throws {
    let architectures = try processRunner.output(
      "/usr/bin/lipo",
      arguments: ["-archs", binary.path]
    ).split(whereSeparator: \.isWhitespace).map(String.init)
    guard architectures.contains(architecture) else {
      throw ArtifactError(
        "Library at \(binary.path) has no \(architecture) architecture."
      )
    }
    if architectures.count == 1 {
      try fileManager.copyItem(at: binary, to: output)
      return
    }
    try processRunner.run(
      "/usr/bin/lipo",
      arguments: [
        binary.path,
        "-thin",
        architecture,
        "-output",
        output.path,
      ]
    )
  }

  private func binary(
    module: String,
    identifier: String,
    frameworks: URL
  ) throws -> URL {
    let xcframework = xcframework(named: module, under: frameworks)
    let library = try metadata(for: xcframework).library(identifier: identifier)
    return xcframework
      .appendingPathComponent(identifier)
      .appendingPathComponent(library.binaryPath)
  }

  private func swiftModule(
    module: String,
    identifier: String,
    frameworks: URL
  ) throws -> URL {
    let xcframework = xcframework(named: module, under: frameworks)
    let library = try metadata(for: xcframework).library(identifier: identifier)
    let result = xcframework
      .appendingPathComponent(identifier)
      .appendingPathComponent(library.libraryPath)
      .appendingPathComponent("Modules/\(module).swiftmodule")
    guard fileManager.fileExists(atPath: result.path) else {
      throw ArtifactError("Swift module is missing at \(result.path).")
    }
    return result
  }

  private func metadata(for xcframework: URL) throws -> XCFrameworkMetadata {
    try XCFrameworkMetadata.load(from: xcframework)
  }

  private func xcframework(named module: String, under directory: URL) -> URL {
    directory.appendingPathComponent("\(module).xcframework")
  }

  private func validateInterfaces(in module: URL, moduleName: String) throws {
    let interfaces = try fileManager.contentsOfDirectory(
      at: module,
      includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "swiftinterface" }
    guard !interfaces.isEmpty else {
      throw ArtifactError("Swift module has no interfaces at \(module.path).")
    }
    for interface in interfaces {
      let contents = try String(contentsOf: interface, encoding: .utf8)
      guard contents.contains("-O") else {
        throw ArtifactError(
          "Swift interface is not optimised at \(interface.path)."
        )
      }
      guard contents.contains("-enable-library-evolution") else {
        throw ArtifactError(
          "Swift interface has no library evolution at \(interface.path)."
        )
      }
      guard contents.contains("-module-name \(moduleName)") else {
        throw ArtifactError(
          "Swift interface has the wrong module name at \(interface.path)."
        )
      }
      guard !contents.contains("-module-alias") else {
        throw ArtifactError(
          "Swift interface contains a module alias at \(interface.path)."
        )
      }
      for original in layout.moduleNames.keys {
        guard !textRewriter.containsModuleReference(original, in: contents)
        else {
          throw ArtifactError(
            "Swift interface contains \(original) at \(interface.path)."
          )
        }
      }
    }
  }

  private func validateSymbols(in library: URL) throws {
    let output = try processRunner.output(
      "/usr/bin/nm",
      arguments: ["-g", library.path]
    )
    let symbols = output.split(separator: "\n").compactMap {
      $0.split(whereSeparator: \.isWhitespace).last.map(String.init)
    }
    guard symbols.contains(where: {
      $0.contains(layout.privateCSymbolPrefix)
    }) else {
      throw ArtifactError(
        "Archive has no private SwiftSyntax C symbols at \(library.path)."
      )
    }
    guard !symbols.contains(where: {
      $0.hasPrefix("swiftsyntax_") || $0.hasPrefix("_swiftsyntax_")
    }) else {
      throw ArtifactError(
        "Archive contains a public SwiftSyntax C symbol at \(library.path)."
      )
    }
  }

  private func copyLicence(from sourcePackage: URL, to output: URL) throws {
    let licence = sourcePackage.appendingPathComponent("LICENSE.txt")
    guard fileManager.fileExists(atPath: licence.path) else {
      throw ArtifactError("SwiftSyntax licence is missing at \(licence.path).")
    }
    try fileManager.copyItem(
      at: licence,
      to: output.appendingPathComponent("SwiftSyntax-LICENSE.txt")
    )
  }
}
