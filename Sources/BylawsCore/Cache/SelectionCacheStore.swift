package import BylawsSemantics
import Foundation

package actor SelectionCacheStore {
  struct Key: Hashable, Sendable {
    let source: UUID
    let filters: [NameFilter]

    var estimatedBytes: Int {
      256 + filters.reduce(0) { $0 + $1.estimatedBytes }
    }
  }

  private struct Entry {
    var value: (any Sendable)?
    var bytes: Int
    var lastUse: UInt64
    var wasRepeated: Bool
  }

  // Releasing the source projection would make each rule rebuild it.
  private struct Projection {
    let storage: any Sendable
    let bytes: Int
    var users: Int
  }

  private struct Calculation {
    let id: UUID
    let task: Task<any Sendable, any Error>
  }

  private let maximumBytes: Int
  private let historyBudget: Int
  private var entries: [Key: Entry] = [:]
  private var projections: [UUID: Projection] = [:]
  private var calculations: [Key: Calculation] = [:]
  private var sequence: UInt64 = 0
  private var historyBytes = 0
  private var isFinished = false
  package private(set) var retainedBytes = 0

  package init(maximumBytes: UInt) {
    self.maximumBytes = Int(clamping: maximumBytes)
    historyBudget = Int(clamping: maximumBytes) / 16
  }

  package func selection<Element: Named>(
    from source: Selection<Element>,
    filters: [NameFilter]
  ) async throws -> Selection<Element> {
    try Task.checkCancellation()
    guard !isFinished, maximumBytes > 0, !filters.isEmpty,
          !QueryInspection.isEnabled
    else {
      return try await Self.filter(source, through: filters)
    }
    let keys = filters.indices.map { index in
      Key(source: source.storage.identity, filters: Array(filters[...index]))
    }
    let shared = keys.last { entries[$0] != nil }
    let key = shared ?? Key(source: source.storage.identity, filters: filters)
    for observed in keys where observed != key { observe(observed) }
    let prefix: Selection<Element> = try await value(
      from: source.storage,
      for: key
    ) {
      try await Self.filter(source, through: key.filters)
    }
    guard key.filters.count < filters.count else { return prefix }
    return try await Self.filter(
      prefix,
      through: Array(filters.dropFirst(key.filters.count))
    )
  }

  package func finish() async {
    isFinished = true
    let pending = calculations.values.map(\.task)
    calculations.removeAll()
    entries.removeAll()
    projections.removeAll()
    retainedBytes = 0
    historyBytes = 0
    for task in pending { task.cancel() }
    for task in pending { _ = await task.result }
  }

  private func observe(_ key: Key) {
    sequence &+= 1
    if entries[key] != nil {
      entries[key]?.lastUse = sequence
      entries[key]?.wasRepeated = true
      return
    }
    let bytes = key.estimatedBytes
    guard bytes <= historyBudget else { return }
    while historyBytes > historyBudget - bytes {
      guard let oldest = entries.filter({ $0.value.value == nil })
        .min(by: { $0.value.lastUse < $1.value.lastUse })?.key
      else { break }
      remove(oldest)
    }
    makeRoom(for: bytes)
    entries[key] = Entry(
      value: nil,
      bytes: bytes,
      lastUse: sequence,
      wasRepeated: false
    )
    retainedBytes += bytes
    historyBytes += bytes
  }

  func value<Element: Sendable>(
    from source: SelectionStorage<Element>,
    for key: Key,
    build: @escaping @Sendable () async throws -> Selection<Element>
  ) async throws -> Selection<Element> {
    observe(key)
    if let existing = entries[key]?.value as? Selection<Element> {
      return existing
    }
    let calculation: Calculation
    if let existing = calculations[key] {
      calculation = existing
    } else {
      calculation = Calculation(
        id: UUID(),
        task: Task(name: "Bylaws shared selection") { @concurrent in
          try await build()
        }
      )
      calculations[key] = calculation
    }
    do {
      let result = try await calculation.task.value
      guard let selection = result as? Selection<Element> else {
        preconditionFailure("A selection key must keep its element type.")
      }
      if calculations[key]?.id == calculation.id {
        calculations[key] = nil
        if entries[key]?.wasRepeated == true {
          store(selection, from: source, for: key)
        }
      }
      try Task.checkCancellation()
      return selection
    } catch {
      if calculations[key]?.id == calculation.id { calculations[key] = nil }
      throw error
    }
  }

  private func store<Element>(
    _ selection: Selection<Element>,
    from source: SelectionStorage<Element>,
    for key: Key
  ) {
    let elementStride = MemoryLayout<Element>.stride
    let projectionBytes = 128 + source.elements.capacity * elementStride
    let selectionBytes = selection.storage === source ? 0
      : selection.storage.elements.capacity * elementStride
    let bytes = key.estimatedBytes + selectionBytes
      + selection.queryDescription.utf8.count
    guard !isFinished, bytes <= maximumBytes,
          projectionBytes <= maximumBytes - bytes
    else { return }
    remove(key)
    while retainedBytes > maximumBytes - bytes
      - (projections[key.source] == nil ? projectionBytes : 0)
    {
      guard let oldest = oldestEntry else { return }
      remove(oldest)
    }
    if projections[key.source] != nil {
      projections[key.source]?.users += 1
    } else {
      projections[key.source] = Projection(
        storage: source,
        bytes: projectionBytes,
        users: 1
      )
      retainedBytes += projectionBytes
    }
    sequence &+= 1
    entries[key] = Entry(
      value: selection,
      bytes: bytes,
      lastUse: sequence,
      wasRepeated: true
    )
    retainedBytes += bytes
  }

  private var oldestEntry: Key? {
    entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key
  }

  private func makeRoom(for bytes: Int) {
    while retainedBytes > maximumBytes - bytes {
      guard let oldest = oldestEntry else { return }
      remove(oldest)
    }
  }

  private func remove(_ key: Key) {
    guard let entry = entries.removeValue(forKey: key) else { return }
    retainedBytes -= entry.bytes
    if entry.value == nil {
      historyBytes -= entry.bytes
    } else if let projection = projections[key.source] {
      if projection.users == 1 {
        projections[key.source] = nil
        retainedBytes -= projection.bytes
      } else {
        projections[key.source]?.users -= 1
      }
    }
  }

  @concurrent
  private static func filter<Element: Named>(
    _ selection: Selection<Element>,
    through filters: [NameFilter]
  ) async throws -> Selection<Element> {
    try Task.checkCancellation()
    let result = selection.filtering(filters)
    try Task.checkCancellation()
    return result
  }
}
