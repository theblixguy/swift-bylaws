package import BylawsSemantics
package import Foundation

extension ParseCache {
  struct MetadataRecord: Codable {
    let metadata: SourceMetadata
    let contentKey: String
  }

  package func collect(
    at path: String,
    swiftLanguageMode: SwiftLanguageMode = .v6,
    now: Date = Date()
  ) async throws(ParseError) -> SourceFile {
    let before = validation == .metadata ? SourceMetadata.read(at: path) : nil
    if let before, before.canReuse(at: now),
       let cached = await sourceFile(
         at: path, matching: before, swiftLanguageMode: swiftLanguageMode
       )
    {
      return cached
    }

    let source = try FileCollector.readSource(atPath: path)
    let key = Self.key(forSource: source, swiftLanguageMode: swiftLanguageMode)
    let file: SourceFile
    if let cached = await sourceFile(forKey: key, at: path),
       cached.sourceText == source,
       cached.swiftLanguageMode == swiftLanguageMode
    {
      file = cached
    } else {
      file = try FileCollector.collect(
        source: source, path: path, swiftLanguageMode: swiftLanguageMode
      )
      await store(file, forKey: key)
    }
    if let before, before.canReuse(at: now),
       before == SourceMetadata.read(at: path)
    {
      let record = MetadataRecord(metadata: before, contentKey: key)
      if let data = try? JSONEncoder().encode(record) {
        await storage.store(data, for: Self.metadataKey(
          for: path, swiftLanguageMode: swiftLanguageMode
        ))
      }
    }
    return file
  }

  func sourceFile(
    at path: String,
    matching metadata: SourceMetadata,
    swiftLanguageMode: SwiftLanguageMode
  ) async -> SourceFile? {
    let key = Self.metadataKey(for: path, swiftLanguageMode: swiftLanguageMode)
    guard let entry = await storage.entry(for: key), let data = entry.data,
          let record = try? JSONDecoder().decode(
            MetadataRecord.self,
            from: data
          ),
          record.metadata == metadata,
          let file = await sourceFile(forKey: record.contentKey, at: path),
          file.swiftLanguageMode == swiftLanguageMode,
          metadata == SourceMetadata.read(at: path)
    else { return nil }
    return file
  }

  static func metadataKey(
    for path: String, swiftLanguageMode: SwiftLanguageMode
  ) -> String {
    "metadata1:" + digest(for: path, swiftLanguageMode: swiftLanguageMode)
  }

  func sourceFile(
    forKey key: String,
    at path: String
  ) async -> SourceFile? {
    guard let entry = await storage.entry(for: key),
          let data = entry.data
    else {
      return nil
    }
    do {
      let decoder = try CacheDecoder(Array(data), path: path)
      let file = try SourceFile(from: decoder)
      return decoder.isAtEnd ? file : nil
    } catch {
      return nil
    }
  }

  func store(_ file: SourceFile, forKey key: String) async {
    let encoder = CacheEncoder()
    encoder.encode(file)
    await storage.store(Data(encoder.bytes), for: key)
  }
}
