package struct SourceLineTable: Sendable {
  private let starts: [Int]
  private let ends: [Int]

  package var count: Int { starts.count }

  package init(_ bytes: some Collection<UInt8>) {
    var starts = [0]
    var ends: [Int] = []
    var previousWasCR = false
    for (offset, byte) in bytes.enumerated() {
      if byte == 0x0A, previousWasCR {
        starts[starts.count - 1] = offset + 1
      } else if byte == 0x0A || byte == 0x0D {
        ends.append(offset)
        starts.append(offset + 1)
      }
      previousWasCR = byte == 0x0D
    }
    ends.append(bytes.count)
    self.starts = starts
    self.ends = ends
  }

  package func range(ofLine line: Int) -> Range<Int>? {
    guard line > 0, line <= starts.count else { return nil }
    return starts[line - 1]..<ends[line - 1]
  }

  package func offset(line: Int, column: Int) -> Int? {
    guard column > 0, let range = range(ofLine: line),
          column - 1 <= range.count
    else { return nil }
    return range.lowerBound + column - 1
  }

  package func location(at offset: Int) -> (line: Int, column: Int) {
    var low = 0
    var high = starts.count
    while high - low > 1 {
      let middle = (low + high) / 2
      if starts[middle] <= offset {
        low = middle
      } else {
        high = middle
      }
    }
    return (line: low + 1, column: offset - starts[low] + 1)
  }
}
