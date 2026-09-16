import ArgumentParser
import BylawsCore
import Testing
@testable import bylaws_cli

@Suite("Cache size options")
struct CacheSizeTests {
  @Test("Whole sizes use decimal and binary units", arguments: [
    ("0", 0), ("123", 123), ("42B", 42), ("2kb", 2000),
    ("3MB", 3_000_000), ("1GB", 1_000_000_000),
    ("2KiB", 2048), ("3mib", 3_145_728), ("1GiB", 1_073_741_824),
  ])
  func sizes(argument: String, bytes: Int) throws {
    let command = try LintCommand.parse(["--cache-size", argument])
    #expect(command.cacheSize?.bytes == bytes)
  }

  @Test("Unsupported sizes fail parsing", arguments: [
    "", "-1", "1.5GB", "1 GB", "1TB", "MB", "9223372036854775807GB",
    "999999999999999999999999999999999", "+1", "１２３",
  ])
  func rejectsSize(argument: String) {
    #expect(throws: (any Error).self) {
      try LintCommand.parse(["--cache-size", argument])
    }
  }

  @Test("Size option takes a value")
  func missingValue() {
    #expect(throws: (any Error).self) {
      try LintCommand.parse(["--cache-size"])
    }
  }

  @Test(
    "Validation option selects the shared cache mode",
    arguments: ["metadata", "content"]
  )
  func validationMode(argument: String) throws {
    let command = try LintCommand.parse(["--cache-validation", argument])
    #expect(command.cacheValidation == ParseCacheConfiguration
      .Validation(rawValue: argument))
  }

  @Test("Unsupported validation mode fails parsing")
  func unknownValidation() {
    #expect(throws: (any Error).self) {
      try LintCommand.parse(["--cache-validation", "fast"])
    }
  }

  @Test("Changed paths accept several values")
  func changedPaths() throws {
    let command = try LintCommand.parse([
      "--changed-path", "Sources/App.swift", "Sources/Feature.swift",
    ])

    #expect(command.changedPaths == [
      "Sources/App.swift", "Sources/Feature.swift",
    ])
  }
}
