struct IndexOccurrences: Sendable {
  private let values: [IndexReference]
  private let indicesByUSR: [String: [Int]]

  init(_ references: some Sequence<IndexReference>) {
    let values = references.sorted(by: IndexReference.areInStableOrder)
    self.values = values
    indicesByUSR = Dictionary(
      grouping: values.indices,
      by: { values[$0].symbol.usr }
    )
  }

  func matching(_ identifiers: Set<String>) -> [IndexReference] {
    identifiers.flatMap { indicesByUSR[$0] ?? [] }.sorted().map { values[$0] }
  }

  func at(file: String, line: Int, column: Int) -> [IndexReference] {
    let position = (file, line, column)
    var lower = 0
    var upper = values.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      let reference = values[middle]
      if (reference.file, reference.line, reference.column) < position {
        lower = middle + 1
      } else {
        upper = middle
      }
    }
    var end = lower
    while end < values.count {
      let reference = values[end]
      guard (reference.file, reference.line, reference.column) == position
      else { break }
      end += 1
    }
    return Array(values[lower..<end])
  }

  var groups: some Sequence<[IndexReference]> {
    indicesByUSR.keys.sorted().lazy.map { identifier in
      (indicesByUSR[identifier] ?? []).map { values[$0] }
    }
  }
}
