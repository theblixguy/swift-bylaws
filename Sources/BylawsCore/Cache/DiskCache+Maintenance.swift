import Foundation

extension DiskCache {
  private static let maintenanceInterval: TimeInterval = 24 * 60 * 60
  private static let maintenanceStampName = "last-trim"

  func removeOldEntriesWhenDue(
    removingEntriesWhere isObsolete: (URL) -> Bool
  ) -> Bool {
    let stamp = entryURL(named: Self.maintenanceStampName)
    let stampDate = Self.attributes(of: stamp, [.contentModificationDateKey])?
      .contentModificationDate
    let previousBudget = data(forEntryNamed: Self.maintenanceStampName)
      .flatMap { Int(String(decoding: $0, as: UTF8.self)) }
    if let stampDate, let previousBudget, budget == previousBudget,
       Date().timeIntervalSince(stampDate) < Self.maintenanceInterval
    {
      return false
    }
    removeOldEntries(removingEntriesWhere: isObsolete)
    try? write(
      Data(String(budget).utf8),
      toEntryNamed: Self.maintenanceStampName
    )
    return true
  }

  func removeOldEntries(
    removingEntriesWhere isObsolete: (URL) -> Bool
  ) {
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
      guard url.lastPathComponent != Self.maintenanceStampName else {
        continue
      }
      guard let values = Self.attributes(of: url, Set(keys)),
            values.isRegularFile == true,
            let size = values.fileSize,
            let date = values.contentModificationDate
      else { continue }
      if isObsolete(url) {
        try? manager.removeItem(at: url)
      } else {
        dated.append((url, date, size))
      }
    }
    var total = dated.reduce(0) { $0 + $1.size }
    guard total > budget else { return }

    dated.sort { $0.date < $1.date }
    for entry in dated {
      try? manager.removeItem(at: entry.url)
      total -= entry.size
      if total <= budget { break }
    }
  }

  private static func attributes(
    of url: URL,
    _ keys: Set<URLResourceKey>
  ) -> URLResourceValues? {
    try? url.resourceValues(forKeys: keys)
  }
}
