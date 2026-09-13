public import Foundation

/// A temporary directory populated with source files for a test.
///
/// The project removes its directory when its last reference is released.
public final class TemporaryProject: Sendable {
  /// The temporary project's root directory.
  public let rootURL: URL

  /// Creates a uniquely named temporary project and writes its files.
  ///
  /// - Parameters:
  ///   - files: File contents keyed by paths relative to the project root.
  ///   - parentDirectory: The directory in which to create the project.
  ///   - directoryNamePrefix: The prefix for the unique directory name.
  /// - Throws: An error when the directory or one of its files cannot be written.
  public init(
    files: [String: String],
    under parentDirectory: URL = FileManager.default.temporaryDirectory,
    directoryNamePrefix: String = "bylaws-test"
  ) throws {
    rootURL = parentDirectory.appendingPathComponent(
      "\(directoryNamePrefix)-\(UUID().uuidString)"
    )
    do {
      try FileManager.default.createDirectory(
        at: rootURL,
        withIntermediateDirectories: true
      )
      for (relativePath, contents) in files {
        try write(contents, to: relativePath)
      }
    } catch {
      try? FileManager.default.removeItem(at: rootURL)
      throw error
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: rootURL)
  }

  /// Returns the URL for a path relative to the project root.
  public func fileURL(for relativePath: String) -> URL {
    rootURL.appendingPathComponent(relativePath)
  }

  /// Writes a UTF-8 file at a path relative to the project root.
  public func write(_ contents: String, to relativePath: String) throws {
    let file = fileURL(for: relativePath)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: file, atomically: true, encoding: .utf8)
  }

  /// Removes the file at a path relative to the project root.
  public func removeFile(at relativePath: String) throws {
    try FileManager.default.removeItem(at: fileURL(for: relativePath))
  }
}
