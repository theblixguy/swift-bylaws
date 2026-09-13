import BylawsCore
import Foundation

final class ParseCacheTestStorage {
  let cache: ParseCache
  let directory: URL

  init(budget: Int = ParseCache.defaultBudget) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("bylaws-parse-cache-tests")
      .appendingPathComponent(UUID().uuidString)
    cache = try ParseCache.opening(directory: directory, budget: budget)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }
}
