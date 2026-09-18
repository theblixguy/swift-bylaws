import Foundation

package struct XCFrameworkMetadata: Decodable, Sendable {
  package struct Library: Decodable, Sendable {
    package let binaryPath: String
    package let libraryIdentifier: String
    package let libraryPath: String
    package let supportedArchitectures: [String]

    private enum CodingKeys: String, CodingKey {
      case binaryPath = "BinaryPath"
      case libraryIdentifier = "LibraryIdentifier"
      case libraryPath = "LibraryPath"
      case supportedArchitectures = "SupportedArchitectures"
    }
  }

  package let availableLibraries: [Library]

  private enum CodingKeys: String, CodingKey {
    case availableLibraries = "AvailableLibraries"
  }

  package static func load(from xcframework: URL) throws -> Self {
    let info = xcframework.appendingPathComponent("Info.plist")
    do {
      return try PropertyListDecoder().decode(
        Self.self,
        from: Data(contentsOf: info)
      )
    } catch {
      throw ArtifactError(
        "Cannot read XCFramework metadata at \(info.path): \(error)"
      )
    }
  }

  package func library(identifier: String) throws -> Library {
    guard let library = availableLibraries.first(where: {
      $0.libraryIdentifier == identifier
    }) else {
      throw ArtifactError("XCFramework has no \(identifier) library.")
    }
    return library
  }
}
