import ArgumentParser
import BylawsCore
import Testing
@testable import bylaws_cli

@Suite("Selection cache size option")
struct SelectionCacheOptionTests {
  @Test("Budget accepts bytes and size units", arguments: [
    ("0", 0),
    ("0MiB", 0),
    ("33554432", 33_554_432),
    ("42B", 42),
    ("2kb", 2000),
    ("3MB", 3_000_000),
    ("1GB", 1_000_000_000),
    ("2KiB", 2048),
    ("32mib", 33_554_432),
    ("1GiB", 1_073_741_824),
    (String(Int.max), Int.max),
  ])
  func size(value: String, expectedBytes: Int) throws {
    let command = try LintCommand.parse(["--selection-cache-size", value])
    #expect(command.selectionCacheSize == UInt(expectedBytes))
    #expect(!command.cache)
  }

  @Test("Absent option keeps default budget")
  func defaultBudget() throws {
    let command = try LintCommand.parse([])
    #expect(command.selectionCacheSize == SelectionCache.defaultBudget)
  }

  @Test(
    "Malformed budgets produce argument errors",
    arguments: [
      "", "-1", "lots", "1.5", "1.5GB", "1 GB", "1TB", "MB", "+1", "１２３",
      "9223372036854775807GB", "999999999999999999999999999999999",
    ]
  )
  func malformed(value: String) {
    #expect(throws: (any Error).self) {
      try LintCommand.parse(["--selection-cache-size", value])
    }
  }

  @Test("Missing size produces argument error")
  func missingValue() {
    #expect(throws: (any Error).self) {
      try LintCommand.parse(["--selection-cache-size"])
    }
  }
}
