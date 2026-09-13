package import BylawsCore
package import BylawsPaths
import Foundation

package enum ProjectRoot {
  package static func resolve(
    explicit: String?,
    hasExplicitRuleFiles: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws(CodebaseError) -> LexicalFilePath {
    if let explicit {
      var isDirectory: ObjCBool = false
      guard unsafe FileManager.default.fileExists(
        atPath: explicit,
        isDirectory: &isDirectory
      ), isDirectory.boolValue else {
        throw .notADirectory(path: explicit)
      }
      return LexicalFilePath(explicit, relativeTo: .currentDirectory)
    }
    if let workspace = environment["BUILD_WORKSPACE_DIRECTORY"],
       !workspace.isEmpty
    {
      return LexicalFilePath(workspace, relativeTo: .currentDirectory)
    }
    do {
      return LexicalFilePath(try Codebase.automaticRoot(at: .currentDirectory))
    } catch {
      // Explicit rules files need no project marker. Without one, the
      // working directory anchors their paths.
      guard hasExplicitRuleFiles else { throw error }
      return .currentDirectory
    }
  }
}
