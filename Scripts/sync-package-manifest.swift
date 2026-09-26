import Foundation

private struct PluginToolConfiguration: Decodable {
  enum Mode: String, Decodable {
    case remote
    case source
  }

  let mode: Mode
  let url: String?
  let checksum: String?
}

private struct SwiftSyntaxConfiguration: Decodable {
  let mode: String
  let swiftCompilerVersion: String
  let swiftSyntaxVersion: String
  let artifactRevision: Int
  let swiftArtifactChecksum: String?
  let cArtifactChecksum: String?
}

private func replaceValue(
  after declaration: String,
  with value: String,
  in source: String
) throws -> String {
  guard let declarationRange = source.range(of: declaration),
        let openingQuote = source[declarationRange.upperBound...]
        .firstIndex(of: "\""),
        let closingQuote = source[source.index(after: openingQuote)...]
        .firstIndex(of: "\"")
  else {
    throw ManifestError.missing(declaration)
  }
  var result = source
  result.replaceSubrange(
    source.index(after: openingQuote)..<closingQuote,
    with: value
  )
  return result
}

private func replaceMode(
  with mode: PluginToolConfiguration.Mode,
  in source: String
) throws -> String {
  let declaration = "static let mode: Mode = ."
  guard let start = source.range(of: declaration),
        let end = source[start.upperBound...].firstIndex(of: "\n")
  else {
    throw ManifestError.missing(declaration)
  }
  var result = source
  result.replaceSubrange(start.upperBound..<end, with: mode.rawValue)
  return result
}

private func checkSwiftSyntax(
  in source: String,
  at root: URL,
  decoder: JSONDecoder
) throws {
  for (swiftVersion, file) in [
    ("v6_2", "602"), ("v6_3", "603"),
    ("v6_4", "604"), ("v6_5", "605"),
  ] {
    let url = root
      .appendingPathComponent("Distribution/SwiftSyntax/\(file).json")
    let configuration = try decoder.decode(
      SwiftSyntaxConfiguration.self,
      from: Data(contentsOf: url)
    )
    let label = "case .\(swiftVersion):"
    guard let start = source.range(of: label),
          let end = source.range(
            of: "\n      case ",
            range: start.upperBound..<source.endIndex
          ) ?? source.range(
            of: "\n      }",
            range: start.upperBound..<source.endIndex
          )
    else {
      throw ManifestError.missing(label)
    }
    let body = source[start.upperBound..<end.lowerBound]
      .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    let values = [
      "mode:.\(configuration.mode)",
      "swiftCompilerVersion:\"\(configuration.swiftCompilerVersion)\"",
      "swiftSyntaxVersion:\"\(configuration.swiftSyntaxVersion)\"",
      "artifactRevision:\(configuration.artifactRevision)",
      "swiftArtifactChecksum:\(configuration.swiftArtifactChecksum.map { "\"\($0)\"" } ?? "nil")",
      "cArtifactChecksum:\(configuration.cArtifactChecksum.map { "\"\($0)\"" } ?? "nil")",
    ]
    guard values.allSatisfy(body.contains) else {
      throw ManifestError.outOfSync(url.lastPathComponent)
    }
  }
}

private enum ManifestError: Error, CustomStringConvertible {
  case missing(String)
  case incompletePluginArtifact
  case outOfSync(String)

  var description: String {
    switch self {
    case let .missing(name):
      "Cannot find \(name) in Package.swift."
    case .incompletePluginArtifact:
      "PluginTool.json must have a URL and checksum in remote mode."
    case let .outOfSync(name):
      "Update Package.swift to match \(name)."
    }
  }
}

private func run() throws {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let manifest = root.appendingPathComponent("Package.swift")
  let decoder = JSONDecoder()
  let plugin = try decoder.decode(
    PluginToolConfiguration.self,
    from: Data(contentsOf: root
      .appendingPathComponent("Distribution/PluginTool.json"))
  )
  let current = try String(contentsOf: manifest, encoding: .utf8)
  var updated = try replaceMode(with: plugin.mode, in: current)
  if plugin.mode == .remote {
    guard let url = plugin.url, let checksum = plugin.checksum else {
      throw ManifestError.incompletePluginArtifact
    }
    updated = try replaceValue(
      after: "static let url =",
      with: url,
      in: updated
    )
    updated = try replaceValue(
      after: "static let checksum =",
      with: checksum,
      in: updated
    )
  }
  try checkSwiftSyntax(in: updated, at: root, decoder: decoder)
  if CommandLine.arguments.dropFirst().first == "--check" {
    guard current == updated else {
      throw ManifestError.outOfSync("PluginTool.json")
    }
  } else if current != updated {
    try updated.write(to: manifest, atomically: true, encoding: .utf8)
  }
}

do {
  try run()
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
