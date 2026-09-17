import BylawsSemantics
import Crypto
package import Foundation

package struct DiskCache: Sendable {
  package enum Error: Swift.Error, Hashable, Sendable {
    case directoryIsSymbolicLink(path: String)
    case directoryIsNotADirectory(path: String)
    case directoryUnavailable(path: String, reason: String)
    case entryIsSymbolicLink(path: String)
    case entryUnavailable(path: String, reason: String)
  }

  package let directory: URL
  package let budget: Int

  package static func key(for value: String) -> String {
    key(for: Data(value.utf8))
  }

  package static func key(for data: Data) -> String {
    SHA256.hash(data: data)
      .map { byte in
        let hex = String(byte, radix: 16)
        return hex.count == 1 ? "0" + hex : hex
      }
      .joined()
  }

  package static func opening(
    directory: URL,
    budget: Int
  ) throws(Error) -> Self {
    let ownedDirectory = directory.appendingPathComponent("Bylaws")
    try prepareDirectory(ownedDirectory)
    return Self(directory: ownedDirectory, budget: budget)
  }

  package func data(forEntryNamed name: String) -> Data? {
    let url = entryURL(named: name)
    guard !Self.isSymbolicLink(url) else { return nil }
    return try? Data(contentsOf: url)
  }

  package func write(
    _ data: Data,
    toEntryNamed name: String
  ) throws(Error) {
    let url = entryURL(named: name)
    guard !Self.isSymbolicLink(url) else {
      throw .entryIsSymbolicLink(path: url.path)
    }
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw .entryUnavailable(
        path: url.path,
        reason: error.reportableDescription
      )
    }
  }

  package func removeEntry(named name: String) throws(Error) {
    let url = entryURL(named: name)
    guard !Self.isSymbolicLink(url) else {
      throw .entryIsSymbolicLink(path: url.path)
    }
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    } catch {
      throw .entryUnavailable(
        path: url.path,
        reason: error.reportableDescription
      )
    }
  }

  func entryURL(named name: String) -> URL {
    directory.appendingPathComponent(name)
  }

  private static func prepareDirectory(
    _ directory: URL
  ) throws(Error) {
    guard !isSymbolicLink(directory) else {
      throw .directoryIsSymbolicLink(path: directory.path)
    }
    let isDirectory: Bool
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      isDirectory = try directory.resourceValues(forKeys: [.isDirectoryKey])
        .isDirectory == true
    } catch {
      throw .directoryUnavailable(
        path: directory.path,
        reason: error.reportableDescription
      )
    }
    guard isDirectory else {
      throw .directoryIsNotADirectory(path: directory.path)
    }
  }

  private static func isSymbolicLink(_ url: URL) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path))
      != nil
  }
}

extension DiskCache.Error: CustomStringConvertible {
  package var description: String {
    switch self {
    case let .directoryIsSymbolicLink(path):
      "cache directory '\(path)' is a symbolic link"
    case let .directoryIsNotADirectory(path):
      "cache directory '\(path)' is not a directory"
    case let .directoryUnavailable(path, reason):
      "cannot use cache directory '\(path)': \(reason)"
    case let .entryIsSymbolicLink(path):
      "cache entry '\(path)' is a symbolic link, so remove it before running Bylaws again"
    case let .entryUnavailable(path, reason):
      "cannot update cache entry '\(path)': \(reason)"
    }
  }
}
