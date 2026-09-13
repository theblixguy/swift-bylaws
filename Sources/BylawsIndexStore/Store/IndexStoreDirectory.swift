package import BylawsPaths
package import Foundation

package enum IndexStoreDirectory {
  package static func isStore(
    _ store: LexicalFilePath
  ) throws(IndexStoreError) -> Bool {
    try !versionDirectories(in: store).isEmpty
  }

  // An index write can leave the store directory's mtime unchanged.
  package static func lastWritten(
    _ store: LexicalFilePath
  ) throws(IndexStoreError) -> Date? {
    var dates: [Date] = []
    for version in try versionDirectories(in: store) {
      if let date = try modificationDate(
        of: store.appending("\(version)/units").string
      ) {
        dates.append(date)
      }
    }
    if let newest = dates.max() { return newest }
    return try modificationDate(of: store.string)
  }

  package static func directoryContents(
    at directory: LexicalFilePath
  ) throws(IndexStoreError) -> [String]? {
    try readingFileSystem(at: directory.string, orMissing: nil) {
      try FileManager.default.contentsOfDirectory(atPath: directory.string)
    }
  }

  private static func versionDirectories(
    in store: LexicalFilePath
  ) throws(IndexStoreError) -> [String] {
    guard let entries = try directoryContents(at: store) else { return [] }
    var versions: [String] = []
    for entry in entries {
      guard entry.first == "v",
            !entry.dropFirst().isEmpty,
            entry.dropFirst().allSatisfy(\.isNumber)
      else { continue }
      if try isDirectory(store.appending(entry).string) {
        versions.append(entry)
      }
    }
    return versions
  }

  private static func isDirectory(
    _ path: String
  ) throws(IndexStoreError) -> Bool {
    try readingFileSystem(at: path, orMissing: false) {
      try URL(fileURLWithPath: path)
        .resourceValues(forKeys: [.isDirectoryKey])
        .isDirectory == true
    }
  }

  private static func modificationDate(
    of path: String
  ) throws(IndexStoreError) -> Date? {
    try readingFileSystem(at: path, orMissing: nil) {
      try FileManager.default.attributesOfItem(atPath: path)[.modificationDate]
        as? Date
    }
  }

  // The read closure throws Foundation errors alone. Those render
  // through localizedDescription.
  private static func readingFileSystem<Value>(
    at path: String,
    orMissing missing: Value,
    _ read: () throws -> Value
  ) throws(IndexStoreError) -> Value {
    do {
      return try read()
    } catch {
      guard !isMissing(error, at: path) else { return missing }
      throw .unreadablePath(path: path, reason: error.localizedDescription)
    }
  }

  // Foundation can report a path below a regular file, such as the
  // SwiftPM lock file, as an unknown read error.
  private static func isMissing(_ error: any Error, at path: String) -> Bool {
    let error = error as NSError
    if error.domain == NSCocoaErrorDomain,
       error.code == NSFileNoSuchFileError
       || error.code == NSFileReadNoSuchFileError
    {
      return true
    }
    return !FileManager.default.fileExists(atPath: path)
  }
}
