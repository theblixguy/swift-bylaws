import Foundation
import SystemPackage

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

package struct LexicalFilePath: Sendable, Hashable {
  private let path: FilePath

  package init(_ path: String) {
    self.path = FilePath(path).lexicallyNormalized()
  }

  package init(_ path: String, relativeTo directory: Self) {
    self.path = directory.path.pushing(FilePath(path)).lexicallyNormalized()
  }

  private init(_ path: FilePath) {
    self.path = path
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
    Self(self.path.appending(path).lexicallyNormalized())
  }

  package func contains(_ candidate: Self) -> Bool {
    candidate.path.starts(with: path)
  }

  package func contains(component name: String) -> Bool {
    path.components.contains { $0.string == name }
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
