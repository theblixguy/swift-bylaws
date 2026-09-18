import Foundation

struct XCFrameworkMetadata: Decodable, Sendable {
  struct Library: Decodable, Sendable {
    let binaryPath: String
    let libraryIdentifier: String
    let libraryPath: String
    let supportedArchitectures: [String]

    private enum CodingKeys: String, CodingKey {
      case binaryPath = "BinaryPath"
      case libraryIdentifier = "LibraryIdentifier"
      case libraryPath = "LibraryPath"
      case supportedArchitectures = "SupportedArchitectures"
    }
  }

  let availableLibraries: [Library]

  private enum CodingKeys: String, CodingKey {
    case availableLibraries = "AvailableLibraries"
  }

  static func load(from xcframework: URL) throws -> Self {
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

  func library(identifier: String) throws -> Library {
    guard let library = availableLibraries.first(where: {
      $0.libraryIdentifier == identifier
    }) else {
      throw ArtifactError("XCFramework has no \(identifier) library.")
    }
    return library
  }
}
