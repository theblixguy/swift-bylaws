import Foundation

package struct ArtifactConfiguration: Decodable, Equatable, Sendable {
  package enum Mode: String, Decodable, Sendable {
    case remote
    case source
  }

  package let mode: Mode
  package let swiftCompilerVersion: String
  package let swiftSyntaxVersion: String
  package let sourceRevision: String
  package let artifactRevision: Int
  package let checksum: String?

  package static func load(from url: URL) throws -> Self {
    let configuration: Self
    do {
      configuration = try JSONDecoder().decode(
        Self.self,
        from: Data(contentsOf: url)
      )
    } catch {
      throw ArtifactError("Cannot read configuration at \(url.path): \(error)")
    }
    try configuration.validate()
    return configuration
  }

  package var swiftSyntaxMajorVersion: String {
    swiftSyntaxVersion.split(separator: ".", maxSplits: 1)[0].description
  }

  private func validate() throws {
    let compilerParts = swiftCompilerVersion.split(separator: ".")
    guard compilerParts.count == 2,
          compilerParts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
          let compilerMinor = Int(compilerParts[1])
    else {
      throw ArtifactError(
        "Swift compiler version must contain a major and minor version."
      )
    }
    let expectedSuffix = "\(compilerParts[0])\(String(format: "%02d", compilerMinor))"
    guard swiftSyntaxMajorVersion == expectedSuffix else {
      throw ArtifactError(
        "SwiftSyntax \(swiftSyntaxVersion) does not match Swift \(swiftCompilerVersion)."
      )
    }
    guard sourceRevision.count == 40,
          sourceRevision.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
    else {
      throw ArtifactError("SwiftSyntax source revision must be a commit ID.")
    }
    guard artifactRevision > 0 else {
      throw ArtifactError("Artifact revision must be greater than zero.")
    }
    switch mode {
    case .source:
      guard checksum == nil else {
        throw ArtifactError("A source configuration cannot contain a checksum.")
      }
    case .remote:
      guard let checksum,
            checksum.count == 64,
            checksum.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
      else {
        throw ArtifactError(
          "A remote configuration must contain a SHA-256 checksum."
        )
      }
    }
  }
}
