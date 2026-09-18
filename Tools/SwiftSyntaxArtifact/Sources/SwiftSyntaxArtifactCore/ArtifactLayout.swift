struct ArtifactLayout: Sendable {
  struct Module: Equatable, Sendable {
    let name: String
    let sourceDirectory: String
  }

  var artifactName: String {
    "BylawsSwiftSyntaxArtifact"
  }

  var cModule: String {
    "BylawsSwiftSyntaxCShims"
  }

  var swiftModules: [Module] {
    [
      module("SwiftSyntax"),
      module("SwiftParser"),
      module("SwiftDiagnostics"),
      module("SwiftBasicFormat"),
      module("SwiftParserDiagnostics"),
      module("SwiftOperators"),
    ]
  }

  var moduleNames: [String: String] {
    Dictionary(uniqueKeysWithValues: swiftModules.map {
      ($0.sourceDirectory, $0.name)
    } + [("_SwiftSyntaxCShims", cModule)])
  }

  var privateCSymbolPrefix: String {
    "bylaws_swiftsyntax_"
  }

  var packageManifest: String {
    let syntax = moduleName(for: "SwiftSyntax")
    let parser = moduleName(for: "SwiftParser")
    let diagnostics = moduleName(for: "SwiftDiagnostics")
    let basicFormat = moduleName(for: "SwiftBasicFormat")
    let parserDiagnostics = moduleName(for: "SwiftParserDiagnostics")
    let operators = moduleName(for: "SwiftOperators")
    return """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
      name: "\(artifactName)",
      platforms: [.macOS(.v14), .iOS(.v13)],
      products: [
        .library(name: "\(syntax)", targets: ["\(syntax)"]),
        .library(name: "\(parser)", targets: ["\(parser)"]),
        .library(name: "\(diagnostics)", targets: ["\(diagnostics)"]),
        .library(name: "\(basicFormat)", targets: ["\(basicFormat)"]),
        .library(
          name: "\(parserDiagnostics)",
          targets: ["\(parserDiagnostics)"]
        ),
        .library(name: "\(operators)", targets: ["\(operators)"]),
      ],
      targets: [
        .target(
          name: "\(cModule)",
          path: "Sources/_SwiftSyntaxCShims"
        ),
        .target(
          name: "\(syntax)",
          dependencies: ["\(cModule)"],
          path: "Sources/SwiftSyntax"
        ),
        .target(
          name: "\(parser)",
          dependencies: ["\(syntax)"],
          path: "Sources/SwiftParser"
        ),
        .target(
          name: "\(diagnostics)",
          dependencies: ["\(syntax)"],
          path: "Sources/SwiftDiagnostics"
        ),
        .target(
          name: "\(basicFormat)",
          dependencies: ["\(syntax)"],
          path: "Sources/SwiftBasicFormat"
        ),
        .target(
          name: "\(parserDiagnostics)",
          dependencies: [
            "\(basicFormat)",
            "\(diagnostics)",
            "\(parser)",
            "\(syntax)",
          ],
          path: "Sources/SwiftParserDiagnostics"
        ),
        .target(
          name: "\(operators)",
          dependencies: [
            "\(diagnostics)",
            "\(parser)",
            "\(syntax)",
          ],
          path: "Sources/SwiftOperators"
        ),
      ]
    )
    """
  }

  func moduleName(for sourceDirectory: String) -> String {
    "Bylaws\(sourceDirectory)"
  }

  private func module(_ sourceDirectory: String) -> Module {
    Module(
      name: moduleName(for: sourceDirectory),
      sourceDirectory: sourceDirectory
    )
  }
}
