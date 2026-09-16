package import BylawsSemantics
package import Foundation

package struct ParseCache: Sendable {
  package static let defaultBudget = ParseCacheConfiguration.defaultBudget

  // Increase this when the model or a collector changes.
  private static let schemaVersion = 11
  private static let keySeparator: UInt8 = 0
  private static let entryVersionMarker = "-v"
  private static let entryNameExtension = ".pack"

  private let disk: DiskCache
  let storage: ParseCacheStore
  let validation: ParseCacheConfiguration.Validation

  package var directory: URL { disk.directory }
  package var budget: Int { disk.budget }

  package static func opening(
    directory: URL,
    budget: Int = ParseCache.defaultBudget,
    validation: ParseCacheConfiguration.Validation = .metadata
  ) throws(DiskCache.Error) -> ParseCache {
    let disk = try DiskCache.opening(directory: directory, budget: budget)
    return ParseCache(disk: disk, validation: validation)
  }

  package static func opening(
    forRoot rootPath: String,
    policy: ParseCachePolicy
  ) -> ParseCache? {
    guard let settings = policy.settings(forRoot: rootPath),
          let disk = try? DiskCache.opening(
            directory: settings.directory,
            budget: settings.budget
          )
    else { return nil }
    return ParseCache(disk: disk, validation: settings.validation)
  }

  private init(
    disk: DiskCache,
    validation: ParseCacheConfiguration.Validation
  ) {
    self.disk = disk
    self.validation = validation
    storage = ParseCacheStore(
      directory: disk.directory,
      schemaVersion: Self.schemaVersion
    )
  }

  package func removeOldEntriesWhenDue() async {
    await storage.flush()
    guard disk.removeOldEntriesWhenDue(
      removingEntriesWhere: Self.isObsoleteEntry
    ) else { return }
    await storage.compactIfNeeded()
    await storage.reload()
  }

  package func removeOldEntries() async {
    await storage.flush()
    disk.removeOldEntries(removingEntriesWhere: Self.isObsoleteEntry)
    await storage.compactIfNeeded()
    await storage.reload()
  }

  private static func isObsoleteEntry(_ url: URL) -> Bool {
    url.pathExtension == "bin"
      || schemaVersion(ofEntryNamed: url.lastPathComponent)
      .map { $0 != schemaVersion } == true
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
    return DiskCache.key(for: Data(bytes))
  }
}
