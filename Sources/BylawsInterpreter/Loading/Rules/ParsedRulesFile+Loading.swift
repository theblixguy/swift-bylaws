import BylawsCore
import BylawsPaths
import BylawsSemantics
import Foundation

extension ParsedRulesFile {
  var discoveryOutsideRootDiagnostic: Diagnostic? {
    discovery.map {
      .error(
        "RuleDiscovery must be declared in the root Bylaws.swift",
        at: $0.location,
        hint: "move the declaration to the project root"
      )
    }
  }

  static func loaded(at path: String, overlay: SourceOverlay) -> Self {
    do {
      let source = try overlay.text(forFileAt: path)
        ?? String(contentsOfFile: path, encoding: .utf8)
      return RulesFileParser.parse(source: source, path: path)
    } catch {
      var parsed = Self(
        path: path,
        directory: LexicalFilePath(path).removingLastComponent().string
      )
      parsed.diagnostics.append(
        .error(
          "cannot read the file: " + error.reportableDescription,
          at: .start(of: path)
        )
      )
      return parsed
    }
  }
}
