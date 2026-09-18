import BylawsSyntax

/// The Swift language mode used to parse a source file.
public enum SwiftLanguageMode: String, Sendable, Hashable, Codable,
  CaseIterable
{
  /// Swift 4 syntax.
  case v4 = "4"

  /// Swift 5 syntax.
  case v5 = "5"

  /// Swift 6 syntax.
  case v6 = "6"

  func parse(_ source: String) -> SourceFileSyntax {
    let version: Parser.SwiftVersion = switch self {
    case .v4: .v4
    case .v5: .v5
    case .v6: .v6
    }
    var parser = Parser(source, swiftVersion: version)
    return SourceFileSyntax.parse(from: &parser)
  }

  package init(toolsVersion: PackageManifest.ToolsVersion?) {
    guard let toolsVersion else {
      self = .v6
      return
    }
    self = if toolsVersion < .init(5, 0) { .v4 }
    else if toolsVersion < .init(6, 0) { .v5 }
    else { .v6 }
  }
}
