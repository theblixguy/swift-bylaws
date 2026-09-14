package import BylawsSemantics

package protocol CacheCodable {
  init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed)
  func encode(to encoder: CacheEncoder)
}

// The ordered format decodes faster than Codable for these cache entries.
package final class CacheEncoder {
  package private(set) var bytes: [UInt8] = []

  package init() {}

  package func encode(_ value: some CacheCodable) {
    value.encode(to: self)
  }

  package func encode(_ value: Bool) {
    bytes.append(value ? 1 : 0)
  }

  package func encode(_ value: Int) {
    var zigzag = UInt64(bitPattern: Int64(value) << 1 ^ Int64(value) >> 63)
    while zigzag >= 0x80 {
      bytes.append(UInt8(zigzag & 0x7F) | 0x80)
      zigzag >>= 7
    }
    bytes.append(UInt8(zigzag))
  }

  package func encode(_ value: String) {
    let utf8 = value.utf8
    encode(utf8.count)
    bytes.append(contentsOf: utf8)
  }
}

package final class CacheDecoder {
  package struct Malformed: Error {}

  package let path: String

  package let source: SourceBuffer

  private var cursor: Cursor

  package init(_ bytes: [UInt8], path: String) throws(Malformed) {
    var cursor = Cursor(bytes: bytes)
    self.path = path
    source = SourceBuffer(try cursor.decodeString())
    self.cursor = cursor
  }

  package var isAtEnd: Bool { cursor.isAtEnd }

  package func decode<Value: CacheCodable>() throws(Malformed) -> Value {
    try Value(from: self)
  }

  package func decodeBool() throws(Malformed) -> Bool {
    try cursor.decodeBool()
  }

  package func decodeInt() throws(Malformed) -> Int {
    try cursor.decodeInt()
  }

  package func decodeString() throws(Malformed) -> String {
    try cursor.decodeString()
  }

  package func decodeCount() throws(Malformed) -> Int {
    try cursor.decodeCount()
  }

  private struct Cursor {
    let bytes: [UInt8]
    var position = 0

    var isAtEnd: Bool { position == bytes.count }

    mutating func decodeBool() throws(Malformed) -> Bool {
      switch try readByte() {
      case 0: return false
      case 1: return true
      default: throw Malformed()
      }
    }

    mutating func decodeInt() throws(Malformed) -> Int {
      var zigzag: UInt64 = 0
      var shift: UInt64 = 0
      while true {
        let byte = try readByte()
        zigzag |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 { break }
        shift += 7
        if shift > 63 { throw Malformed() }
      }
      let value = Int64(bitPattern: zigzag >> 1) ^
        -Int64(bitPattern: zigzag & 1)
      return Int(value)
    }

    mutating func decodeString() throws(Malformed) -> String {
      let count = try decodeCount()
      let start = position
      position += count
      return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    mutating func decodeCount() throws(Malformed) -> Int {
      let count = try decodeInt()
      guard count >= 0, count <= bytes.count - position else {
        throw Malformed()
      }
      return count
    }

    private mutating func readByte() throws(Malformed) -> UInt8 {
      guard position < bytes.count else { throw Malformed() }
      defer { position += 1 }
      return bytes[position]
    }
  }
}

extension Bool: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self = try decoder.decodeBool()
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(self)
  }
}

extension Int: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self = try decoder.decodeInt()
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(self)
  }
}

extension String: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    self = try decoder.decodeString()
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(self)
  }
}

extension Range<Int>: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    let lower = try decoder.decodeInt()
    let upper = try decoder.decodeInt()
    guard lower <= upper else { throw CacheDecoder.Malformed() }
    self = lower..<upper
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(lowerBound)
    encoder.encode(upperBound)
  }
}

extension Optional: CacheCodable where Wrapped: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    guard try decoder.decodeBool() else {
      self = nil
      return
    }
    let value: Wrapped = try decoder.decode()
    self = value
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(self != nil)
    if let value = self { encoder.encode(value) }
  }
}

extension Array: CacheCodable where Element: CacheCodable {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    let count = try decoder.decodeCount()
    self = []
    reserveCapacity(count)
    for _ in 0..<count { append(try decoder.decode()) }
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(count)
    for element in self { encoder.encode(element) }
  }
}

extension CacheCodable where Self: RawRepresentable, RawValue == String {
  package init(from decoder: CacheDecoder) throws(CacheDecoder.Malformed) {
    guard let value = Self(rawValue: try decoder.decodeString()) else {
      throw CacheDecoder.Malformed()
    }
    self = value
  }

  package func encode(to encoder: CacheEncoder) {
    encoder.encode(rawValue)
  }
}
