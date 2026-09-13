import Foundation
import SystemPackage

// readdir supplies an entry's type without FileManager's costly attributes.
package enum DirectoryWalker {
  package enum Entry: Sendable {
    case directory
    case regularFile
  }

  package enum Step {
    case descend
    case skipDescendants
  }

  package struct UnopenableDirectory: Sendable {
    package let relativePath: String
    package let reason: String
  }

  package static func walk(
    _ rootPath: String,
    visit: (_ relativePath: String, _ entry: Entry) -> Step
  ) async -> [UnopenableDirectory] {
    var level = [""]
    var unopenable: [UnopenableDirectory] = []
    while !level.isEmpty {
      let listings = await listings(of: level, underRoot: rootPath)
      for (directory, listing) in zip(level, listings) {
        guard case let .failure(failure) = listing else { continue }
        unopenable.append(
          UnopenableDirectory(
            relativePath: directory,
            reason: message(forErrorCode: failure.code)
          )
        )
      }
      level = nextLevel(visiting: listings, of: level, visit)
    }
    return unopenable
  }

  private static let maximumConcurrentDirectoryTasks = min(
    32,
    max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
  )

  private typealias Listing = [(name: String, kind: Entry)]

  private struct OpenFailure: Error {
    let code: CInt
  }

  private enum ClassifiedEntry {
    case included(Entry)
    case ignored
  }

  private static func listings(
    of directories: [String],
    underRoot rootPath: String
  ) async -> [Result<Listing, OpenFailure>] {
    await boundedConcurrentMap(
      directories,
      maximumConcurrentTasks: maximumConcurrentDirectoryTasks
    ) { directory in
      contents(ofDirectoryAt: directory, underRoot: rootPath)
    }
  }

  private static func nextLevel(
    visiting listings: [Result<Listing, OpenFailure>],
    of directories: [String],
    _ visit: (String, Entry) -> Step
  ) -> [String] {
    var next: [String] = []
    for (directory, listing) in zip(directories, listings) {
      for (name, kind) in (try? listing.get()) ?? [] {
        let relativePath = directory.isEmpty ? name : "\(directory)/\(name)"
        let step = visit(relativePath, kind)
        if kind == .directory, step == .descend {
          next.append(relativePath)
        }
      }
    }
    return next
  }

  private static func contents(
    ofDirectoryAt directory: String,
    underRoot rootPath: String
  ) -> Result<Listing, OpenFailure> {
    let path = directory.isEmpty ? rootPath : "\(rootPath)/\(directory)"
    errno = 0
    guard let stream = unsafe opendir(path) else {
      return .failure(OpenFailure(code: errno))
    }
    defer { unsafe closedir(stream) }

    var entries: Listing = []
    while true {
      errno = 0
      guard let entry = unsafe readdir(stream) else {
        return errno == 0
          ? .success(entries) : .failure(OpenFailure(code: errno))
      }
      let name = unsafe name(of: entry.pointee)
      if name == "." || name == ".." { continue }
      switch unsafe kind(
        of: entry.pointee.d_type,
        at: "\(path)/\(name)"
      ) {
      case let .included(kind):
        entries.append((name, kind))
      case .ignored:
        break
      }
    }
  }

  private static func message(forErrorCode code: CInt) -> String {
    unsafe String(cString: strerror(code))
  }

  private static func name(of entry: dirent) -> String {
    // Swift 6.4 rejects the outer unsafe marker that Swift 6.2 and 6.3 require.
    #if compiler(>=6.4)
      withUnsafeBytes(of: entry.d_name) { bytes in
        unsafe String(cString: bytes.baseAddress!
          .assumingMemoryBound(to: CChar.self))
      }
    #else
      unsafe withUnsafeBytes(of: entry.d_name) { bytes in
        unsafe String(cString: bytes.baseAddress!
          .assumingMemoryBound(to: CChar.self))
      }
    #endif
  }

  // Symbolic links can loop or re-enter an excluded tree.
  private static func kind(of type: UInt8, at path: String) -> ClassifiedEntry {
    switch type {
    case UInt8(DT_DIR): return .included(.directory)
    case UInt8(DT_REG): return .included(.regularFile)
    case UInt8(DT_UNKNOWN):
      guard let type = try? FilePath(path).stat(
        followTargetSymlink: false
      ).type else { return .ignored }
      switch type {
      case .directory: return .included(.directory)
      case .regular: return .included(.regularFile)
      default: return .ignored
      }
    default: return .ignored
    }
  }
}
