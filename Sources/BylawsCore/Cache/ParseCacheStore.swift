import Foundation

actor ParseCacheStore {
  enum Entry: Sendable {
    case memory(Data)
    case packed(ParseCachePack, key: String)

    var data: Data? {
      switch self {
      case let .memory(data): data
      case let .packed(pack, key): pack.value(for: key)
      }
    }
  }

  private struct State {
    var entries: [String: ParseCachePack] = [:]
    var pending: [String: Data] = [:]
    var pendingBytes = 0
  }

  private static let batchSize = 4 * 1024 * 1024
  private let directory: URL
  private let suffix: String
  private var state: State

  init(directory: URL, schemaVersion: Int) {
    self.directory = directory
    suffix = "-v\(schemaVersion).pack"
    var initial = State()
    for url in Self.files(in: directory, suffix: suffix) {
      guard let pack = try? ParseCachePack(url: url) else { continue }
      for key in pack.entries.keys { initial.entries[key] = pack }
    }
    state = initial
  }

  func entry(for key: String) -> Entry? {
    if let pending = state.pending[key] { return .memory(pending) }
    return state.entries[key].map { .packed($0, key: key) }
  }

  func store(_ value: Data, for key: String) {
    state.pendingBytes -= state.pending[key]?.count ?? 0
    state.pending[key] = value
    state.pendingBytes += value.count
    if state.pendingBytes >= Self.batchSize { flushPending() }
  }

  func flush() {
    flushPending()
  }

  func reload() {
    state.entries.removeAll()
    for url in Self.files(in: directory, suffix: suffix) {
      guard let pack = try? ParseCachePack(url: url) else { continue }
      for key in pack.entries.keys { state.entries[key] = pack }
    }
  }

  func compactIfNeeded() {
    flushPending()
    let files = Self.files(in: directory, suffix: suffix)
    guard files.count > 64 else { return }
    var entries: [String: ParseCachePack] = [:]
    for url in files {
      guard let pack = try? ParseCachePack(url: url) else { continue }
      for key in pack.entries.keys { entries[key] = pack }
    }
    let liveBytes = entries.reduce(0) { total, entry in
      total + (entry.value.entries[entry.key]?.count ?? 0)
    }
    let expectedCount = liveBytes / Self.batchSize + 1
    guard expectedCount < files.count / 2 else { return }
    var values: [String: Data] = [:]
    var byteCount = 0
    var replacement: [String: ParseCachePack] = [:]
    do {
      for (key, pack) in entries.sorted(by: { $0.key < $1.key }) {
        guard let value = pack.value(for: key) else { continue }
        values[key] = value
        byteCount += value.count
        if byteCount >= Self.batchSize {
          let pack = try publish(values)
          for key in pack.entries.keys { replacement[key] = pack }
          values.removeAll()
          byteCount = 0
        }
      }
      if !values.isEmpty {
        let pack = try publish(values)
        for key in pack.entries.keys { replacement[key] = pack }
      }
    } catch { return }
    state.entries = replacement
    for file in files { try? FileManager.default.removeItem(at: file) }
  }

  private func flushPending() {
    guard !state.pending.isEmpty else { return }
    if let pack = try? publish(state.pending) {
      for key in pack.entries.keys { state.entries[key] = pack }
    }
    state.pending.removeAll()
    state.pendingBytes = 0
  }

  private func publish(_ values: [String: Data]) throws -> ParseCachePack {
    try ParseCachePack.write(
      values, to: directory.appendingPathComponent(UUID().uuidString + suffix)
    )
  }

  private static func files(in directory: URL, suffix: String) -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []
    return files.filter { $0.lastPathComponent.hasSuffix(suffix) }
      .map { url in
        let values = try? url.resourceValues(
          forKeys: [.contentModificationDateKey]
        )
        return (url, values?.contentModificationDate ?? .distantPast)
      }
      .sorted {
        ($0.1, $0.0.lastPathComponent) < ($1.1, $1.0.lastPathComponent)
      }
      .map(\.0)
  }
}
