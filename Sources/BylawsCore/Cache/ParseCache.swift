package import BylawsSemantics
import Crypto
package import Foundation

package struct ParseCache: Sendable {
  package static let defaultBudget = ParseCacheConfiguration.defaultBudget

  // Increase this when the model or a collector changes.
  private static let schemaVersion = 11
  private static let maintenanceInterval: TimeInterval = 24 * 60 * 60
  private static let keySeparator: UInt8 = 0
  private static let entryVersionMarker = "-v"
  private static let entryNameExtension = ".pack"

  package let directory: URL
  package let budget: Int
  let storage: ParseCacheStore
  let validation: ParseCacheConfiguration.Validation

  package static func opening(
    directory: URL,
    budget: Int = ParseCache.defaultBudget,
    validation: ParseCacheConfiguration.Validation = .metadata
  ) throws(ParseCacheError) -> ParseCache {
    let ownedDirectory = directory.appendingPathComponent("Bylaws")
    try prepareDirectory(ownedDirectory)
    return ParseCache(
      cacheDirectory: ownedDirectory, budget: budget, validation: validation
    )
  }

  private init(
    cacheDirectory: URL,
    budget: Int,
    validation: ParseCacheConfiguration.Validation
  ) {
    directory = cacheDirectory
    self.budget = budget
    self.validation = validation
    storage = ParseCacheStore(
      directory: cacheDirectory,
      schemaVersion: Self.schemaVersion
    )
  }

  package func removeOldEntriesWhenDue() async {
    await storage.flush()
    let stamp = directory.appendingPathComponent("last-trim")
    let stampDate = Self.attributes(of: stamp, [.contentModificationDateKey])?
      .contentModificationDate
    let previousBudget = (try? Data(contentsOf: stamp))
      .flatMap { Int(String(decoding: $0, as: UTF8.self)) }
    if let stampDate, let previousBudget, budget == previousBudget,
       Date().timeIntervalSince(stampDate) < Self.maintenanceInterval
    {
      return
    }
    await removeOldEntries()
    Self.writeFile(Data(String(budget).utf8), to: stamp)
  }

  package func removeOldEntries() async {
    await storage.flush()
    trim()
    await storage.compactIfNeeded()
    await storage.reload()
  }

  private func trim() {
    let manager = FileManager.default
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
    ]
    guard let walker = manager.enumerator(
      at: directory,
      includingPropertiesForKeys: keys
    ) else { return }

    var dated: [(url: URL, date: Date, size: Int)] = []
    for case let url as URL in walker {
      guard url.lastPathComponent != "last-trim" else { continue }
      guard let values = Self.attributes(of: url, Set(keys)),
            values.isRegularFile == true,
            let size = values.fileSize,
            let date = values.contentModificationDate
      else { continue }
      if url.pathExtension == "bin"
        || Self.schemaVersion(ofEntryNamed: url.lastPathComponent)
        .map({ $0 != Self.schemaVersion }) == true
      {
        Self.removeFile(at: url)
        continue
      }
      dated.append((url, date, size))
    }
    var total = dated.reduce(0) { $0 + $1.size }
    guard total > budget else { return }

    dated.sort { $0.date < $1.date }
    for entry in dated {
      Self.removeFile(at: entry.url)
      total -= entry.size
      if total <= budget { break }
    }
  }

  private static func schemaVersion(ofEntryNamed fileName: String) -> Int? {
    guard fileName.hasSuffix(entryNameExtension),
          let marker = fileName.range(
            of: entryVersionMarker,
            options: .backwards
          )
    else { return nil }
    return Int(
      fileName[marker.upperBound...].dropLast(entryNameExtension.count)
    )
  }

  package static func key(
    forSource source: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  ) -> String {
    digest(for: source, swiftLanguageMode: swiftLanguageMode)
  }

  static func digest(
    for text: String,
    swiftLanguageMode: SwiftLanguageMode
  ) -> String {
    var bytes = Array(swiftLanguageMode.rawValue.utf8)
    bytes.append(keySeparator)
    bytes.append(contentsOf: text.utf8)
    return SHA256.hash(data: Data(bytes))
      .map { byte in
        let hex = String(byte, radix: 16)
        return hex.count == 1 ? "0" + hex : hex
      }
      .joined()
  }

  private static func prepareDirectory(
    _ directory: URL
  ) throws(ParseCacheError) {
    // Cache cleanup could delete files outside the cache through a symbolic link.
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

  private static func attributes(
    of url: URL,
    _ keys: Set<URLResourceKey>
  ) -> URLResourceValues? {
    try? url.resourceValues(forKeys: keys)
  }

  private static func writeFile(_ data: Data, to url: URL) {
    try? data.write(to: url, options: .atomic)
  }

  private static func removeFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
}

package enum ParseCacheError: Error, Hashable, Sendable {
  case directoryIsSymbolicLink(path: String)
  case directoryIsNotADirectory(path: String)
  case directoryUnavailable(path: String, reason: String)
}

extension ParseCacheError: CustomStringConvertible {
  package var description: String {
    switch self {
    case let .directoryIsSymbolicLink(path):
      "the cache directory '\(path)' is a symbolic link"
    case let .directoryIsNotADirectory(path):
      "the cache directory '\(path)' is not a directory"
    case let .directoryUnavailable(path, reason):
      "the cache directory '\(path)' could not be created: \(reason)"
    }
  }
}
