import Crypto
import Foundation

struct ParseCachePack: Sendable {
  struct Entry: Codable, Sendable {
    let offset: Int
    let count: Int
    let digest: Data
  }

  private static let marker = Data("BylawsPack1".utf8)
  let bytes: Data
  let entries: [String: Entry]

  init(url: URL) throws {
    // Published packs stay immutable while readers retain their mappings.
    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
    let trailerCount = Self.marker.count + MemoryLayout<UInt64>.size
    guard bytes.count >= trailerCount,
          bytes.suffix(Self.marker.count) == Self.marker
    else { throw CocoaError(.fileReadCorruptFile) }
    let lengthEnd = bytes.count - Self.marker.count
    let lengthStart = lengthEnd - MemoryLayout<UInt64>.size
    let indexCount = bytes[lengthStart..<lengthEnd].enumerated()
      .reduce(UInt64(0)) {
        $0 | UInt64($1.element) << ($1.offset * 8)
      }
    guard indexCount <= lengthStart else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let indexStart = lengthStart - Int(indexCount)
    let entries = try JSONDecoder().decode(
      [String: Entry].self, from: bytes[indexStart..<lengthStart]
    )
    guard entries.values.allSatisfy({
      $0.offset >= 0 && $0.count > 0 && $0.offset <= indexStart
        && $0.count <= indexStart - $0.offset && $0.digest.count == 32
    }) else { throw CocoaError(.fileReadCorruptFile) }
    self.bytes = bytes
    self.entries = entries
  }

  static func write(_ values: [String: Data], to url: URL) throws -> Self {
    var bytes = Data()
    var entries: [String: Entry] = [:]
    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
      entries[key] = Entry(
        offset: bytes.count, count: value.count,
        digest: digest(for: key, value: value)
      )
      bytes.append(value)
    }
    let index = try JSONEncoder().encode(entries)
    bytes.append(index)
    let count = UInt64(index.count)
    for shift in stride(from: 0, to: 64, by: 8) {
      bytes.append(UInt8(truncatingIfNeeded: count >> shift))
    }
    bytes.append(marker)
    try bytes.write(to: url, options: .atomic)
    return try Self(url: url)
  }

  func value(for key: String) -> Data? {
    guard let entry = entries[key] else { return nil }
    let value = bytes[entry.offset..<(entry.offset + entry.count)]
    guard Self.digest(for: key, value: value) == entry.digest
    else { return nil }
    return value
  }

  private static func digest(for key: String, value: Data) -> Data {
    var hash = SHA256()
    hash.update(data: Data(key.utf8))
    hash.update(data: Data([0]))
    hash.update(data: value)
    return Data(hash.finalize())
  }
}
