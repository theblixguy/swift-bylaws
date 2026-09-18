import Foundation
import SwiftSyntaxArtifactCore
import Testing

@Suite("Source package preparation")
struct SourcePackagePreparerTests {
  @Test("Renames module references and C symbols")
  func renamesModuleReferencesAndCSymbols() throws {
    try withSourceRepository { repository, configuration in
      let output = repository
        .deletingLastPathComponent()
        .appendingPathComponent("Prepared")

      try SourcePackagePreparer(configuration: configuration).prepare(
        source: repository,
        output: output
      )

      let parser = try String(
        contentsOf: output.appendingPathComponent(
          "Sources/SwiftParser/SwiftParser.swift"
        ),
        encoding: .utf8
      )
      #expect(parser.contains("import BylawsSwiftSyntax"))
      #expect(parser.contains("canImport(BylawsSwiftSyntax, _version: 1)"))
      #expect(parser.contains("BylawsSwiftSyntax.TokenSyntax"))
      #expect(parser.contains("bylaws_swiftsyntax_future_api()"))

      let header = try String(
        contentsOf: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/Platform.h"
        ),
        encoding: .utf8
      )
      #expect(header.contains("bylaws_swiftsyntax_future_api"))
      #expect(!header.contains("void swiftsyntax_future_api"))
      #expect(FileManager.default
        .fileExists(atPath: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/bylaws_swiftsyntax_future.h"
        ).path))
      #expect(try String(
        contentsOf: output.appendingPathComponent("LICENSE.txt"),
        encoding: .utf8
      ) == "SwiftSyntax licence")
    }
  }

  @Test("Rejects a different source revision")
  func rejectsDifferentSourceRevision() throws {
    try withSourceRepository { repository, configuration in
      try "change".write(
        to: repository.appendingPathComponent("Change.txt"),
        atomically: true,
        encoding: .utf8
      )
      try ProcessRunner().run(
        "/usr/bin/git",
        arguments: ["add", "."],
        currentDirectory: repository
      )
      try ProcessRunner().run(
        "/usr/bin/git",
        arguments: ["commit", "--quiet", "-m", "Change"],
        currentDirectory: repository
      )
      let revision = try ProcessRunner().output(
        "/usr/bin/git",
        arguments: ["rev-parse", "HEAD"],
        currentDirectory: repository
      )

      #expect(throws: ArtifactError(
        "SwiftSyntax is at \(revision). Use \(configuration.sourceRevision)."
      )) {
        try SourcePackagePreparer(configuration: configuration).prepare(
          source: repository,
          output: repository
            .deletingLastPathComponent()
            .appendingPathComponent("Prepared")
        )
      }
    }
  }
}

private func withSourceRepository(
  _ body: (URL, ArtifactConfiguration) throws -> Void
) throws {
  try withTemporaryDirectory { directory in
    let repository = directory.appendingPathComponent("SwiftSyntax")
    try FileManager.default.createDirectory(
      at: repository,
      withIntermediateDirectories: true
    )
    try writeSourceFiles(to: repository)
    let runner = ProcessRunner()
    try runner.run(
      "/usr/bin/git",
      arguments: ["init", "--quiet"],
      currentDirectory: repository
    )
    try runner.run(
      "/usr/bin/git",
      arguments: ["config", "user.name", "Artifact Tests"],
      currentDirectory: repository
    )
    try runner.run(
      "/usr/bin/git",
      arguments: ["config", "user.email", "artifact-tests@example.com"],
      currentDirectory: repository
    )
    try runner.run(
      "/usr/bin/git",
      arguments: ["add", "."],
      currentDirectory: repository
    )
    try runner.run(
      "/usr/bin/git",
      arguments: ["commit", "--quiet", "-m", "Source"],
      currentDirectory: repository
    )
    let revision = try runner.output(
      "/usr/bin/git",
      arguments: ["rev-parse", "HEAD"],
      currentDirectory: repository
    )
    let configurationURL = directory.appendingPathComponent("604.json")
    try """
    {
      "mode": "source",
      "swiftCompilerVersion": "6.4",
      "swiftSyntaxVersion": "604.0.0",
      "sourceRevision": "\(revision)",
      "artifactRevision": 1
    }
    """.write(
      to: configurationURL,
      atomically: true,
      encoding: .utf8
    )
    try body(
      repository,
      ArtifactConfiguration.load(from: configurationURL)
    )
  }
}

private func writeSourceFiles(to repository: URL) throws {
  try "SwiftSyntax licence".write(
    to: repository.appendingPathComponent("LICENSE.txt"),
    atomically: true,
    encoding: .utf8
  )
  let sources = repository.appendingPathComponent("Sources")
  let modules = [
    "SwiftSyntax",
    "SwiftParser",
    "SwiftDiagnostics",
    "SwiftBasicFormat",
    "SwiftParserDiagnostics",
    "SwiftOperators",
  ]
  for module in modules {
    let directory = sources.appendingPathComponent(module)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let contents = if module == "SwiftParser" {
      """
      @_exported import SwiftSyntax
      #if canImport(SwiftSyntax, _version: 1)
      let token: SwiftSyntax.TokenSyntax? = nil
      swiftsyntax_future_api()
      #endif
      """
    } else {
      "public let value = 1"
    }
    try contents.write(
      to: directory.appendingPathComponent("\(module).swift"),
      atomically: true,
      encoding: .utf8
    )
  }

  let cModule = sources.appendingPathComponent("_SwiftSyntaxCShims")
  let include = cModule.appendingPathComponent("include")
  try FileManager.default.createDirectory(
    at: include,
    withIntermediateDirectories: true
  )
  try "void swiftsyntax_future_api(void);".write(
    to: include.appendingPathComponent("Platform.h"),
    atomically: true,
    encoding: .utf8
  )
  try "void swiftsyntax_future_header(void);".write(
    to: include.appendingPathComponent("swiftsyntax_future.h"),
    atomically: true,
    encoding: .utf8
  )
  try """
  module _SwiftSyntaxCShims {
    header "Platform.h"
    header "swiftsyntax_future.h"
  }
  """.write(
    to: include.appendingPathComponent("module.modulemap"),
    atomically: true,
    encoding: .utf8
  )
  try """
  #include "Platform.h"
  void swiftsyntax_future_api(void) {}
  """.write(
    to: cModule.appendingPathComponent("Platform.c"),
    atomically: true,
    encoding: .utf8
  )
}
