import Foundation
import SwiftSyntaxArtifactCore
import Testing

@Suite("XCFramework validation")
struct XCFrameworkValidatorTests {
  @Test("Accepts compiler modules")
  func acceptsCompilerModules() throws {
    try withSwiftArtifact { artifact, module in
      try Data().write(
        to: module.appendingPathComponent(
          "arm64-apple-macos.swiftmodule"
        )
      )

      try XCFrameworkValidator().validateSwiftArtifact(
        artifact,
        modules: ["BylawsSwiftSyntax"]
      )
    }
  }

  @Test("Rejects library-evolution interfaces")
  func rejectsLibraryEvolutionInterfaces() throws {
    try withSwiftArtifact { artifact, module in
      try Data().write(
        to: module.appendingPathComponent(
          "arm64-apple-macos.swiftmodule"
        )
      )
      try Data().write(
        to: module.appendingPathComponent(
          "arm64-apple-macos.swiftinterface"
        )
      )

      #expect(throws: ArtifactError(
        "Swift module must not contain a library-evolution interface at \(module.path)."
      )) {
        try XCFrameworkValidator().validateSwiftArtifact(
          artifact,
          modules: ["BylawsSwiftSyntax"]
        )
      }
    }
  }

  @Test("Rejects missing architecture modules")
  func rejectsMissingArchitectureModules() throws {
    try withSwiftArtifact { artifact, module in
      #expect(throws: ArtifactError(
        "Swift module must contain an arm64 binary at \(module.path)."
      )) {
        try XCFrameworkValidator().validateSwiftArtifact(
          artifact,
          modules: ["BylawsSwiftSyntax"]
        )
      }
    }
  }
}

private func withSwiftArtifact(
  _ body: (URL, URL) throws -> Void
) throws {
  try withTemporaryDirectory { directory in
    let artifact = directory.appendingPathComponent("Syntax.xcframework")
    let identifier = "macos-arm64"
    let module = artifact
      .appendingPathComponent(identifier)
      .appendingPathComponent("BylawsSwiftSyntax.swiftmodule")
    try FileManager.default.createDirectory(
      at: module,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: artifact
        .appendingPathComponent(identifier)
        .appendingPathComponent("libSyntax.a"),
      withDestinationURL: URL(fileURLWithPath: CommandLine.arguments[0])
    )
    let metadata: [String: Any] = [
      "AvailableLibraries": [[
        "BinaryPath": "libSyntax.a",
        "LibraryIdentifier": identifier,
        "LibraryPath": "libSyntax.a",
        "SupportedArchitectures": ["arm64"],
      ]],
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: metadata,
      format: .xml,
      options: 0
    )
    try data.write(to: artifact.appendingPathComponent("Info.plist"))
    try body(artifact, module)
  }
}
