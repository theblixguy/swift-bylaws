#!/usr/bin/env swift

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private enum BundleLayout {
  static let artifactType = "executable"
  static let bundleExtension = "artifactbundle"
  static let executableDirectory = "bin"
  static let executablePermissions = 0o755
  static let manifestName = "info.json"
  static let schemaVersion = "1.0"
}

private enum InputFormat {
  private static let identifierCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-"
  )
  private static let nameCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  )
  private static let targetTripleCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
  )
  private static let versionCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.+-"
  )

  static func isIdentifier(_ value: String) -> Bool {
    containsOnly(value, characters: identifierCharacters)
  }

  static func isName(_ value: String) -> Bool {
    containsOnly(value, characters: nameCharacters)
  }

  static func isTargetTriple(_ value: String) -> Bool {
    containsOnly(value, characters: targetTripleCharacters)
  }

  static func isVersion(_ value: String) -> Bool {
    containsOnly(value, characters: versionCharacters)
  }

  private static func containsOnly(
    _ value: String,
    characters: CharacterSet
  ) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy(characters.contains)
  }
}

private struct BundleManifest: Encodable {
  let schemaVersion: String
  let artifacts: [String: Artifact]
}

private struct Artifact: Encodable {
  let type: String
  let version: String
  let variants: [Variant]
}

private struct Variant: Encodable {
  let path: String
  let supportedTriples: [String]
}

private struct VariantSpecification {
  static let separator = "::"

  let artifactIdentifier: String
  let executableName: String
  let variantName: String
  let executableURL: URL
  let supportedTriples: [String]

  init(_ value: String) throws {
    let components = value.components(separatedBy: Self.separator)
    guard components.count == 5 else {
      throw CommandFailure(Command.usage)
    }

    artifactIdentifier = components[0]
    guard InputFormat.isIdentifier(artifactIdentifier) else {
      throw CommandFailure(
        "Invalid artifact identifier: \(artifactIdentifier)"
      )
    }

    executableName = components[1]
    guard InputFormat.isName(executableName) else {
      throw CommandFailure("Invalid executable name: \(executableName)")
    }

    variantName = components[2]
    guard InputFormat.isIdentifier(variantName) else {
      throw CommandFailure("Invalid variant name: \(variantName)")
    }

    executableURL = URL(fileURLWithPath: components[3])
    guard let resourceValues = try? executableURL.resourceValues(
      forKeys: [.isRegularFileKey]
    ), resourceValues.isRegularFile == true else {
      throw CommandFailure("Artifact does not exist: \(components[3])")
    }

    supportedTriples = components[4]
      .split(separator: ",", omittingEmptySubsequences: false)
      .map(String.init)
    guard supportedTriples.allSatisfy(InputFormat.isTargetTriple) else {
      let invalidTriple = supportedTriples.first {
        !InputFormat.isTargetTriple($0)
      } ?? components[4]
      throw CommandFailure("Invalid target triple: \(invalidTriple)")
    }
  }

  var relativePath: String {
    [variantName, BundleLayout.executableDirectory, executableName]
      .joined(separator: "/")
  }
}

private enum Command {
  static var usage: String {
    "Usage: \(CommandLine.arguments[0]) VERSION OUTPUT ARTIFACT::EXECUTABLE::VARIANT::PATH::TRIPLE[,TRIPLE...] [...]"
  }
}

private struct CommandFailure: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

private func makeBundle(arguments: [String]) throws {
  guard arguments.count >= 3 else {
    throw CommandFailure(Command.usage)
  }

  let version = arguments[0]
  guard InputFormat.isVersion(version) else {
    throw CommandFailure("Invalid version: \(version)")
  }

  let outputPath = arguments[1]
  let outputURL = URL(fileURLWithPath: outputPath)
  guard outputURL.pathExtension == BundleLayout.bundleExtension else {
    throw CommandFailure("Output must end in .artifactbundle: \(outputPath)")
  }

  let fileManager = FileManager.default
  guard !fileManager.fileExists(atPath: outputURL.path) else {
    throw CommandFailure("Output already exists: \(outputPath)")
  }

  let specifications = try arguments.dropFirst(2).map(
    VariantSpecification.init
  )
  var executableByArtifact: [String: String] = [:]
  var variantsByArtifact: [String: Set<String>] = [:]
  for specification in specifications {
    if let executable = executableByArtifact[specification.artifactIdentifier],
       executable != specification.executableName
    {
      throw CommandFailure(
        "Artifact \(specification.artifactIdentifier) has several executable names."
      )
    }
    executableByArtifact[specification.artifactIdentifier] =
      specification.executableName
    guard variantsByArtifact[
      specification.artifactIdentifier,
      default: []
    ].insert(specification.variantName).inserted else {
      throw CommandFailure(
        "Duplicate variant \(specification.variantName) for artifact \(specification.artifactIdentifier)."
      )
    }
  }

  let outputParent = outputURL.deletingLastPathComponent()
  try fileManager.createDirectory(
    at: outputParent,
    withIntermediateDirectories: true
  )
  let workURL = outputParent.appendingPathComponent(
    ".\(outputURL.lastPathComponent).tmp.\(UUID().uuidString)"
  )
  try fileManager.createDirectory(
    at: workURL,
    withIntermediateDirectories: false
  )
  var shouldRemoveWorkDirectory = true
  defer {
    if shouldRemoveWorkDirectory {
      try? fileManager.removeItem(at: workURL)
    }
  }

  var variantsByIdentifier: [String: [Variant]] = [:]
  for specification in specifications {
    let executableURL = workURL.appendingPathComponent(
      specification.relativePath
    )
    try fileManager.createDirectory(
      at: executableURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try fileManager.copyItem(
      at: specification.executableURL,
      to: executableURL
    )
    try fileManager.setAttributes(
      [
        .posixPermissions: NSNumber(
          value: BundleLayout.executablePermissions
        ),
      ],
      ofItemAtPath: executableURL.path
    )
    variantsByIdentifier[specification.artifactIdentifier, default: []]
      .append(
        Variant(
          path: specification.relativePath,
          supportedTriples: specification.supportedTriples
        )
      )
  }

  let artifacts = variantsByIdentifier.mapValues { variants in
    Artifact(
      type: BundleLayout.artifactType,
      version: version,
      variants: variants
    )
  }
  let manifest = BundleManifest(
    schemaVersion: BundleLayout.schemaVersion,
    artifacts: artifacts
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [
    .prettyPrinted,
    .sortedKeys,
    .withoutEscapingSlashes,
  ]
  var manifestData = try encoder.encode(manifest)
  manifestData.append(0x0A)
  try manifestData.write(
    to: workURL.appendingPathComponent(BundleLayout.manifestName)
  )

  try fileManager.moveItem(at: workURL, to: outputURL)
  shouldRemoveWorkDirectory = false
}

private func stop(with message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(EXIT_FAILURE)
}

do {
  try makeBundle(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CommandFailure {
  stop(with: error.description)
} catch {
  stop(with: error.localizedDescription)
}
