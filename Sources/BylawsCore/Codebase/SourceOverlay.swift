import BylawsPaths

package struct SourceOverlay: Sendable, Hashable {
  package static let empty = SourceOverlay([:])

  package init(_ textsByPath: [String: String]) {
    let directory = LexicalFilePath.currentDirectory
    self.directory = directory
    self.textsByPath = Dictionary(
      textsByPath.map { (Self.key(for: $0.key, in: directory), $0.value) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  package var isEmpty: Bool { textsByPath.isEmpty }

  package var paths: Dictionary<String, String>.Keys { textsByPath.keys }

  package func text(forFileAt path: String) -> String? {
    guard !textsByPath.isEmpty else { return nil }
    return textsByPath[Self.key(for: path, in: directory)]
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.textsByPath == rhs.textsByPath
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(textsByPath)
  }

  private let directory: LexicalFilePath
  private let textsByPath: [String: String]

  private static func key(
    for path: String,
    in directory: LexicalFilePath
  ) -> String {
    LexicalFilePath(path, relativeTo: directory).string
  }
}
