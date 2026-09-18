import Foundation

package struct SourcePackagePreparer {
  private let fileManager = FileManager.default
  private let textRewriter = TextRewriter()
  private let layout = ArtifactLayout()

  package init() {}

  package func prepare(source: URL, output: URL) throws {
    guard !fileManager.fileExists(atPath: output.path) else {
      throw ArtifactError("Output already exists at \(output.path).")
    }
    let work = output
      .deletingLastPathComponent()
      .appendingPathComponent(".\(output.lastPathComponent).\(UUID())")
    try fileManager.createDirectory(
      at: work.appendingPathComponent("Sources"),
      withIntermediateDirectories: true
    )
    var shouldRemoveWork = true
    defer {
      if shouldRemoveWork {
        try? fileManager.removeItem(at: work)
      }
    }

    for module in layout.swiftModules {
      try copySourceDirectory(
        named: module.sourceDirectory,
        from: source,
        to: work
      )
    }
    try copySourceDirectory(named: "_SwiftSyntaxCShims", from: source, to: work)
    try copyLicence(from: source, to: work)

    let sources = work.appendingPathComponent("Sources")
    try removeBuildFiles(from: sources)
    try rewriteSwiftModules(in: sources)
    try rewriteCModule(in: sources.appendingPathComponent("_SwiftSyntaxCShims"))
    try layout.packageManifest.write(
      to: work.appendingPathComponent("Package.swift"),
      atomically: true,
      encoding: .utf8
    )
    try fileManager.moveItem(at: work, to: output)
    shouldRemoveWork = false
  }

  private func copySourceDirectory(
    named name: String,
    from source: URL,
    to output: URL
  ) throws {
    let sourceURL = source.appendingPathComponent("Sources/\(name)")
    let outputURL = output.appendingPathComponent("Sources/\(name)")
    guard fileManager.fileExists(atPath: sourceURL.path) else {
      throw ArtifactError("SwiftSyntax source is missing at \(sourceURL.path).")
    }
    try fileManager.copyItem(at: sourceURL, to: outputURL)
  }

  private func copyLicence(from source: URL, to output: URL) throws {
    let licence = source.appendingPathComponent("LICENSE.txt")
    guard fileManager.fileExists(atPath: licence.path) else {
      throw ArtifactError("SwiftSyntax licence is missing at \(licence.path).")
    }
    try fileManager.copyItem(
      at: licence,
      to: output.appendingPathComponent("LICENSE.txt")
    )
  }

  private func removeBuildFiles(from sources: URL) throws {
    for url in try files(under: sources) where
      url.lastPathComponent == "CMakeLists.txt"
      || url.lastPathComponent == "README.md"
      || url.pathComponents.contains("Documentation.docc")
    {
      try fileManager.removeItem(at: url)
    }
  }

  private func rewriteSwiftModules(in sources: URL) throws {
    let swiftFiles = try files(under: sources).filter {
      $0.pathExtension == "swift"
    }
    for url in swiftFiles {
      var source = try String(contentsOf: url, encoding: .utf8)
      for (original, replacement) in layout.moduleNames {
        source = textRewriter.replacingModuleReferences(
          in: source,
          from: original,
          to: replacement
        )
      }
      source = textRewriter.replacingCPrefix(
        in: source,
        with: layout.privateCSymbolPrefix
      )
      try source.write(to: url, atomically: true, encoding: .utf8)
    }
    try checkSwiftReferences(in: swiftFiles)
  }

  private func checkSwiftReferences(in files: [URL]) throws {
    for url in files {
      let source = try String(contentsOf: url, encoding: .utf8)
      for original in layout.moduleNames.keys {
        guard !textRewriter.containsModuleReference(original, in: source)
        else {
          throw ArtifactError(
            "Source still refers to \(original) at \(url.path)."
          )
        }
      }
      guard !textRewriter.containsOriginalCPrefix(in: source) else {
        throw ArtifactError(
          "Source still contains the SwiftSyntax C prefix at \(url.path)."
        )
      }
    }
  }

  private func rewriteCModule(in source: URL) throws {
    let cFiles = try files(under: source).filter {
      ["c", "h", "modulemap"].contains($0.pathExtension)
        || $0.lastPathComponent == "module.modulemap"
    }
    for url in cFiles {
      var contents = try String(contentsOf: url, encoding: .utf8)
      contents = textRewriter.replacingCModuleName(
        in: contents,
        with: layout.cModule
      )
      contents = textRewriter.replacingCPrefix(
        in: contents,
        with: layout.privateCSymbolPrefix
      )
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }
    for url in cFiles where url.lastPathComponent.hasPrefix("swiftsyntax_") {
      let name = url.lastPathComponent.dropFirst("swiftsyntax_".count)
      try fileManager.moveItem(
        at: url,
        to: url.deletingLastPathComponent().appendingPathComponent(
          "\(layout.privateCSymbolPrefix)\(name)"
        )
      )
    }
    try renameCUmbrellaHeader(in: source)
    try checkCReferences(in: files(under: source))
  }

  private func renameCUmbrellaHeader(in source: URL) throws {
    let original = source.appendingPathComponent("include/SwiftSyntaxCShims.h")
    guard fileManager.fileExists(atPath: original.path) else {
      throw ArtifactError(
        "SwiftSyntax C umbrella header is missing. Use an unmodified SwiftSyntax checkout."
      )
    }
    try fileManager.moveItem(
      at: original,
      to: original
        .deletingLastPathComponent()
        .appendingPathComponent("\(layout.cModule).h")
    )
  }

  private func checkCReferences(in files: [URL]) throws {
    for url in files {
      let contents = try String(contentsOf: url, encoding: .utf8)
      guard !textRewriter.containsCModuleName(in: contents),
            !textRewriter.containsOriginalCPrefix(in: contents)
      else {
        throw ArtifactError(
          "Source still contains an original SwiftSyntax C name at \(url.path)."
        )
      }
    }
  }

  private func files(under directory: URL) throws -> [URL] {
    guard let enumerator = fileManager.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      throw ArtifactError("Cannot read directory at \(directory.path).")
    }
    return try enumerator.compactMap { entry in
      guard let url = entry as? URL else { return nil }
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      return values.isRegularFile == true ? url : nil
    }
  }
}
