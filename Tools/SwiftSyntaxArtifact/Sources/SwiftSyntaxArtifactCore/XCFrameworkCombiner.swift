import Foundation

package struct XCFrameworkCombiner {
  private let fileManager = FileManager.default
  private let processRunner = ProcessRunner()
  private let layout = ArtifactLayout()
  private let validator = XCFrameworkValidator()

  package init() {}

  package func combine(
    frameworks: URL,
    sourcePackage: URL,
    output: URL
  ) throws {
    guard !fileManager.fileExists(atPath: output.path) else {
      throw ArtifactError("Output already exists at \(output.path).")
    }

    let work = output
      .deletingLastPathComponent()
      .appendingPathComponent(".\(output.lastPathComponent).\(UUID())")
    try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: work) }
    let artifacts = work.appendingPathComponent("artifacts")
    try fileManager.createDirectory(
      at: artifacts,
      withIntermediateDirectories: false
    )

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
      let inputLibraries = try layout.swiftModules.map {
        (
          module: $0.name,
          binary: try binary(
            module: $0.name,
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

    let swiftArtifact = artifacts.appendingPathComponent(
      "\(layout.artifactName).xcframework"
    )
    try processRunner.run(
      "/usr/bin/xcodebuild",
      arguments: ["-create-xcframework"] + stagedLibraries.flatMap {
        ["-library", $0.url.path]
      } + ["-output", swiftArtifact.path]
    )

    for (identifier, _) in stagedLibraries {
      for module in layout.swiftModules {
        let source = try swiftModule(
          module: module.name,
          identifier: identifier,
          frameworks: frameworks
        )
        let destination = swiftArtifact
          .appendingPathComponent(identifier)
          .appendingPathComponent("\(module.name).swiftmodule")
        try fileManager.copyItem(at: source, to: destination)
      }
    }
    try validator.validateSwiftArtifact(
      swiftArtifact,
      modules: layout.swiftModules.map(\.name)
    )

    let cArtifact = artifacts.appendingPathComponent(
      "\(layout.cModule).xcframework"
    )
    try fileManager.copyItem(
      at: xcframework(named: layout.cModule, under: frameworks),
      to: cArtifact
    )
    try validator.validateCArtifact(cArtifact)

    try copyLicence(from: sourcePackage, to: swiftArtifact)
    try copyLicence(from: sourcePackage, to: cArtifact)

    try fileManager.createDirectory(
      at: output.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.moveItem(at: artifacts, to: output)
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
