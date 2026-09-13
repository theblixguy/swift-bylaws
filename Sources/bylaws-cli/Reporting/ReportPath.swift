import BylawsCore
import BylawsPaths

enum ReportPath {
  static func relative(_ path: String, to rootPath: String) -> String? {
    guard !rootPath.isEmpty else { return nil }
    return LexicalFilePath(path)
      .relative(to: LexicalFilePath(rootPath))?.string
  }
}
