import BylawsCore
import BylawsPaths
import BylawsSemantics
import Foundation

struct ParsedSourceArchive: Sendable {
  struct Entry: Sendable {
    let relativePath: String
    let sourceFile: SourceFile
  }

  enum Error: Swift.Error, Equatable, CustomStringConvertible {
    case cannotRead(String)
    case cannotWrite(String)
    case duplicatePath(String)
    case pathMustBeRelative(String)
    case unsupportedFormat

    var description: String {
      switch self {
      case let .cannotRead(path):
        "Cannot read the parsed-source archive at '\(path)'."
      case let .cannotWrite(path):
        "Cannot write the parsed-source archive at '\(path)'."
      case let .duplicatePath(path):
        "Parsed-source archives contain more than one file at '\(path)'."
      case let .pathMustBeRelative(path):
        "Parsed-source archive path must be a normalised relative path: '\(path)'."
      case .unsupportedFormat:
        "Parsed-source archive uses an unsupported format. Create it again with this Bylaws version."
      }
    }
  }

  private struct Contents {
    let files: [SourceFile]
    let directories: Set<String>
  }

  private static let formatKey = "\0format"
  private static let sourceKeyPrefix = "\0source:"
  private static let directoryKeyPrefix = "\0directory:"
  private static let directoryValue = Data([0])
  private static let format = Data("1:\(ParseCache.schemaVersion)".utf8)

  private let pack: ParseCachePack
  private let path: String

  init(contentsOf url: URL) throws(Error) {
    do {
      pack = try ParseCachePack(url: url)
    } catch {
      throw .cannotRead(url.path)
    }
    guard pack.value(for: Self.formatKey) == Self.format else {
      throw .unsupportedFormat
    }
    path = url.path
  }

  static func write(
    _ entries: [Entry],
    directories: Set<String> = [],
    to url: URL
  ) throws(Error) {
    var values = [formatKey: format]
    var directories = directories
    for entry in entries {
      guard isPortable(entry.relativePath) else {
        throw .pathMustBeRelative(entry.relativePath)
      }
      let key = sourceKeyPrefix + entry.relativePath
      guard values[key] == nil else { throw .duplicatePath(entry.relativePath) }
      let encoder = CacheEncoder()
      encoder.encode(entry.sourceFile)
      values[key] = Data(encoder.bytes)
      var parent = LexicalFilePath(entry.relativePath)
        .removingLastComponent()
      while !parent.string.isEmpty {
        directories.insert(parent.string)
        parent = parent.removingLastComponent()
      }
    }
    for directory in directories {
      guard isPortable(directory) else {
        throw .pathMustBeRelative(directory)
      }
      var path = LexicalFilePath(directory)
      while !path.string.isEmpty {
        values[directoryKeyPrefix + path.string] = directoryValue
        path = path.removingLastComponent()
      }
    }
    do {
      _ = try ParseCachePack.write(values, to: url)
    } catch {
      throw .cannotWrite(url.path)
    }
  }

  static func load(
    _ archives: [URL],
    rootedAt rootPath: String
  ) throws(Error) -> PreparedSources {
    var files: [SourceFile] = []
    var directories: Set<String> = []
    for url in archives {
      let contents = try ParsedSourceArchive(contentsOf: url)
        .contents(rootedAt: rootPath)
      files += contents.files
      directories.formUnion(contents.directories)
    }
    do {
      return try PreparedSources(files: files, directories: directories)
    } catch {
      switch error {
      case let .duplicatePath(path): throw .duplicatePath(path)
      }
    }
  }

  private func contents(rootedAt rootPath: String) throws(Error) -> Contents {
    var files: [SourceFile] = []
    var directories: Set<String> = []
    for key in pack.keys.sorted() where key != Self.formatKey {
      if key.hasPrefix(Self.directoryKeyPrefix) {
        guard pack.value(for: key) == Self.directoryValue else {
          throw .cannotRead(path)
        }
        let relativePath = String(
          key.dropFirst(Self.directoryKeyPrefix.count)
        )
        guard Self.isPortable(relativePath) else {
          throw .pathMustBeRelative(relativePath)
        }
        directories.insert(
          LexicalFilePath(rootPath).appending(relativePath).string
        )
        continue
      }
      guard key.hasPrefix(Self.sourceKeyPrefix),
            let data = pack.value(for: key)
      else { throw .unsupportedFormat }
      let relativePath = String(key.dropFirst(Self.sourceKeyPrefix.count))
      guard Self.isPortable(relativePath) else {
        throw .pathMustBeRelative(relativePath)
      }
      let sourcePath = LexicalFilePath(rootPath).appending(relativePath).string
      let decoder: CacheDecoder
      let file: SourceFile
      do {
        decoder = try CacheDecoder(Array(data), path: sourcePath)
        file = try SourceFile(from: decoder)
      } catch {
        throw .cannotRead(path)
      }
      guard decoder.isAtEnd else { throw .cannotRead(path) }
      files.append(file)
    }
    return Contents(files: files, directories: directories)
  }

  private static func isPortable(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/") else { return false }
    return path.split(separator: "/", omittingEmptySubsequences: false)
      .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }
}
