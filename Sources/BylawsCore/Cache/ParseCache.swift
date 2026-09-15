package import BylawsSemantics
import Crypto
package import Foundation

package struct ParseCache: Sendable {
  package static let defaultBudget = 1_000_000_000

  // Increase this when the model or a collector changes.
  private static let schemaVersion = 10
  private static let maintenanceInterval: TimeInterval = 24 * 60 * 60
  private static let keySeparator: UInt8 = 0
  private static let entryVersionMarker = "-v"
  private static let entryNameExtension = ".bin"

  package let directory: URL
  package let budget: Int

  package static func opening(
    directory: URL,
    budget: Int = ParseCache.defaultBudget
  ) throws(ParseCacheError) -> ParseCache {
    let ownedDirectory = directory.appendingPathComponent("Bylaws")
    try prepareDirectory(ownedDirectory)
    return ParseCache(cacheDirectory: ownedDirectory, budget: budget)
  }

  private init(
    cacheDirectory: URL,
    budget: Int
  ) {
    directory = cacheDirectory
    self.budget = budget
  }

  package func sourceFile(
    forSource source: String,
    at path: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  ) -> SourceFile? {
    let entry = entry(
      forSource: source,
      swiftLanguageMode: swiftLanguageMode
    )
    guard let bytes = Self.readFile(at: entry) else { return nil }
    guard let file = Self.decodeSourceFile(bytes, at: path) else {
      Self.removeFile(at: entry)
      return nil
    }
    return file
  }

  package func store(_ file: SourceFile) {
    let encoder = CacheEncoder()
    encoder.encode(file)
    Self.writeFile(Data(encoder.bytes), to: entry(
      forSource: file.sourceText, swiftLanguageMode: file.swiftLanguageMode
    ))
  }

  package func removeOldEntriesWhenDue() {
    let stamp = directory.appendingPathComponent("last-trim")
    let stampDate = Self.attributes(of: stamp, [.contentModificationDateKey])?
      .contentModificationDate
    if let stampDate,
       Date().timeIntervalSince(stampDate) < Self.maintenanceInterval
    {
      return
    }
    Self.writeFile(Data(), to: stamp)
    removeOldEntries()
  }

  package func removeOldEntries() {
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
      guard let values = Self.attributes(of: url, Set(keys)),
            values.isRegularFile == true,
            let size = values.fileSize,
            let date = values.contentModificationDate
      else { continue }
      if let version = Self.schemaVersion(ofEntryNamed: url.lastPathComponent),
         version != Self.schemaVersion
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
      if total <= budget { return }
    }
  }

  package func entry(
    forSource source: String,
    swiftLanguageMode: SwiftLanguageMode = .v6
  ) -> URL {
    let key = Self.key(
      forSource: source,
      swiftLanguageMode: swiftLanguageMode
    )
    let name = "\(key)\(Self.entryVersionMarker)\(Self.schemaVersion)"
      + Self.entryNameExtension
    return directory.appendingPathComponent(name)
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
    var bytes = Array(swiftLanguageMode.rawValue.utf8)
    bytes.append(keySeparator)
    bytes.append(contentsOf: source.utf8)
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

  private static func readFile(at url: URL) -> [UInt8]? {
    try? FileCollector.readBytes(atPath: url.path)
  }

  private static func decodeSourceFile(
    _ bytes: [UInt8], at path: String
  ) -> SourceFile? {
    do {
      let decoder = try CacheDecoder(bytes, path: path)
      let file = try SourceFile(from: decoder)
      return decoder.isAtEnd ? file : nil
    } catch {
      return nil
    }
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
