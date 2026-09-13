public import BylawsCore
import BylawsSemantics
import Foundation

extension Baseline {
  /// Returns the entries a recorded baseline file declares.
  ///
  /// Recorded baselines are Swift source. Test targets compile them, and the CLI
  /// interprets them.
  ///
  /// - Throws: ``BylawsFileError`` when the baseline file is unreadable or
  ///   malformed.
  public static func entries(
    fromFile path: String
  ) throws(BylawsFileError) -> [Entry] {
    let source: String
    do {
      source = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
      throw BylawsFileError(
        diagnostics: [
          .error(
            "cannot read the baseline file: "
              + error.reportableDescription,
            at: DeclarationLocation.start(of: path)
          ),
        ]
      )
    }
    switch BaselineFileParser.parse(source: source, path: path) {
    case let .success(entries):
      return entries
    case let .failure(diagnostic):
      throw BylawsFileError(diagnostics: [diagnostic])
    }
  }
}
