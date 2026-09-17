import BylawsPaths
package import BylawsSemantics

package final class PreparedSources: Sendable, Hashable {
  package enum Error: Swift.Error, Equatable, CustomStringConvertible {
    case duplicatePath(String)

    package var description: String {
      switch self {
      case let .duplicatePath(path):
        "Prepared sources contain more than one file at '\(path)'."
      }
    }
  }

  let files: [SourceFile]
  let directories: Set<String>

  package init(
    files: [SourceFile],
    directories: Set<String> = []
  ) throws(Error) {
    var paths: Set<String> = []
    for file in files where !paths.insert(file.path).inserted {
      throw .duplicatePath(file.path)
    }
    self.files = files.sorted { $0.path < $1.path }
    self.directories = directories
  }

  func relativeDirectories(under rootPath: String) -> Set<String> {
    let root = LexicalFilePath(rootPath)
    return Set(directories.compactMap { path in
      guard root.contains(LexicalFilePath(path)) else { return nil }
      return LexicalFilePath(path).relative(to: root)?.string
    })
  }

  package static func == (
    lhs: PreparedSources,
    rhs: PreparedSources
  ) -> Bool {
    lhs === rhs
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}
