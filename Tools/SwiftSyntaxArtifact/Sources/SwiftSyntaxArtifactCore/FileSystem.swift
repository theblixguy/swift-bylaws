import Foundation

package struct FileSystem {
  private let fileManager = FileManager.default

  package func files(under directory: URL) throws -> [URL] {
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
