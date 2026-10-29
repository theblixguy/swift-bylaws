import Foundation
import SystemPackage

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

package struct LexicalFilePath: Sendable, Hashable {
  private let path: FilePath
  private let components: FilePath.ComponentView

  package init(_ path: String) {
    self.init(FilePath(path))
  }

  package init(_ path: String, relativeTo directory: Self) {
    self.init(directory.path.pushing(FilePath(path)))
  }

  private init(_ path: FilePath) {
    let components = path.components
    // FilePath.isLexicallyNormal repeats debug checks on the component view.
    if components.allSatisfy({ $0.kind == .regular }) {
      self.path = path
      self.components = components
    } else {
      let normalised = path.lexicallyNormalized()
      self.path = normalised
      self.components = normalised.components
    }
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.path == rhs.path
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(path)
  }

  package static var currentDirectory: Self {
    Self(FileManager.default.currentDirectoryPath)
  }

  package var string: String {
    path.string
  }

  package var lastComponent: String? {
    path.lastComponent?.string
  }

  package func appending(_ path: String) -> Self {
    Self(self.path.appending(path))
  }

  package func contains(_ candidate: Self) -> Bool {
    path.isEmpty || (path.root == candidate.path.root
      && candidate.components.starts(with: components))
  }

  package func contains(component name: String) -> Bool {
    components.contains { $0.string == name }
  }

  package func relative(to directory: Self) -> Self? {
    var relative = path
    guard relative.removePrefix(directory.path) else { return nil }
    return Self(relative)
  }

  @safe package func resolvingSymbolicLinks() -> Self? {
    guard let resolved = unsafe realpath(string, nil) else { return nil }
    defer { unsafe free(resolved) }
    return Self(unsafe String(cString: resolved))
  }

  package func resolvingDescendant(_ subpath: String) -> Self? {
    let subpath = FilePath(subpath)
    guard subpath.root == nil,
          let resolved = path.lexicallyResolving(subpath)
    else { return nil }
    return Self(resolved)
  }

  package func removingLastComponent() -> Self {
    Self(path.removingLastComponent())
  }
}
