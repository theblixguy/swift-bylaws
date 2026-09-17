import BylawsPaths
import BylawsSemantics
import Foundation

extension Codebase {
  /// Reads a configured Bazel dependency graph from a JSON export.
  ///
  /// Use Bazel 8 or later to generate the export with
  /// `bazel cquery 'deps(//app:app)' --output=jsonproto
  /// --transitions=lite --proto:include_configurations`. Use the build options
  /// for the configuration you want to check and include the full dependency
  /// closure. Regenerate the export before running rules after a build-setting
  /// or dependency change.
  ///
  /// - Parameter path: An absolute path or a path relative to the codebase root.
  /// - Throws: ``CodebaseError`` if the root or export cannot be read, or the
  ///   export omits configured dependencies or their targets.
  @concurrent
  public func bazelGraph(from path: String) async throws(CodebaseError)
    -> BazelGraph
  {
    let rootPath = try resolvedRootPath()
    let file = LexicalFilePath(path, relativeTo: LexicalFilePath(rootPath))
    await recordFileDependency(file.string, projectRoot: rootPath)
    do {
      let data: Data
      if case let .sources(files) = root.strategy {
        guard let relativePath = file.relative(to: LexicalFilePath(rootPath)),
              let text = files[relativePath.string]
        else { throw CocoaError(.fileReadNoSuchFile) }
        data = Data(text.utf8)
      } else {
        data = try Data(contentsOf: URL(fileURLWithPath: file.string))
      }
      let result = try JSONDecoder().decode(BazelQueryResult.self, from: data)
      return try result.graph(rootPath: rootPath, exportPath: file.string)
    } catch is DecodingError {
      throw .bazelGraph(
        path: file.string,
        reason: "The file must contain a configured cquery JSON result."
      )
    } catch {
      throw .bazelGraph(path: file.string, reason: error.reportableDescription)
    }
  }
}
