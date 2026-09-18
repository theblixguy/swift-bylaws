import Foundation
import SwiftSyntaxArtifactCore
import Testing

@Suite("Source package preparation")
struct SourcePackagePreparerTests {
  @Test("Renames SwiftSyntax references")
  func renamesSwiftSyntaxReferences() throws {
    try withSourceDirectory { source in
      let output = source
        .deletingLastPathComponent()
        .appendingPathComponent("Prepared")

      try SourcePackagePreparer().prepare(
        source: source,
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
      #expect(FileManager.default
        .fileExists(atPath: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/BylawsSwiftSyntaxCShims.h"
        ).path))
      #expect(!FileManager.default
        .fileExists(atPath: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/SwiftSyntaxCShims.h"
        ).path))
      let moduleMap = try String(
        contentsOf: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/module.modulemap"
        ),
        encoding: .utf8
      )
      #expect(moduleMap.contains("header \"bylaws_swiftsyntax_future.h\""))
      let umbrellaHeader = try String(
        contentsOf: output.appendingPathComponent(
          "Sources/_SwiftSyntaxCShims/include/BylawsSwiftSyntaxCShims.h"
        ),
        encoding: .utf8
      )
      #expect(umbrellaHeader
        .contains("#include \"bylaws_swiftsyntax_future.h\""))
      #expect(try String(
        contentsOf: output.appendingPathComponent("LICENSE.txt"),
        encoding: .utf8
      ) == "SwiftSyntax licence")
    }
  }

  @Test("Rejects a missing C umbrella header")
  func rejectsMissingCUmbrellaHeader() throws {
    try withSourceDirectory { source in
      let header = source.appendingPathComponent(
        "Sources/_SwiftSyntaxCShims/include/SwiftSyntaxCShims.h"
      )
      try FileManager.default.removeItem(at: header)

      #expect(throws: ArtifactError(
        "SwiftSyntax C umbrella header is missing. Use an unmodified SwiftSyntax checkout."
      )) {
        try SourcePackagePreparer().prepare(
          source: source,
          output: source
            .deletingLastPathComponent()
            .appendingPathComponent("Prepared")
        )
      }
    }
  }
}

private func withSourceDirectory(
  _ body: (URL) throws -> Void
) throws {
  try withTemporaryDirectory { directory in
    let source = directory.appendingPathComponent("SwiftSyntax")
    try FileManager.default.createDirectory(
      at: source,
      withIntermediateDirectories: true
    )
    try writeSourceFiles(to: source)
    try body(source)
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
  try "#include \"swiftsyntax_future.h\"".write(
    to: include.appendingPathComponent("SwiftSyntaxCShims.h"),
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
