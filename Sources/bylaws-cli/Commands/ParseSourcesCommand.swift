import ArgumentParser
import BylawsCore
import BylawsPaths
import BylawsSemantics
import Foundation

struct ParseSourcesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "parse-sources",
    abstract: "Parses Swift sources into an internal archive.",
    shouldDisplay: false
  )

  @Option(
    parsing: .unconditionalSingleValue,
    help: ArgumentHelp(visibility: .hidden)
  )
  var input: [String] = []

  @Option(
    parsing: .unconditionalSingleValue,
    help: ArgumentHelp(visibility: .hidden)
  )
  var path: [String] = []

  @Option(help: ArgumentHelp(visibility: .hidden))
  var swiftLanguageMode = "6"

  @Option(help: ArgumentHelp(visibility: .hidden))
  var output: String

  func run() async throws {
    guard input.count == path.count else {
      throw ValidationError(
        "Each --input must have one matching --path."
      )
    }
    guard let mode = SwiftLanguageMode(rawValue: swiftLanguageMode) else {
      throw ValidationError("Swift language mode must be 4, 5 or 6.")
    }
    let mapped = try await mappedSources()
    let entries = try await boundedConcurrentMap(
      mapped.files,
      maximumConcurrentTasks: max(
        1,
        ProcessInfo.processInfo.activeProcessorCount
      )
    ) { source in
      let text = try FileCollector.readSource(atPath: source.inputPath)
      let file = try FileCollector.collect(
        source: text,
        path: source.relativePath,
        swiftLanguageMode: mode
      )
      return ParsedSourceArchive.Entry(
        relativePath: source.relativePath,
        sourceFile: file
      )
    }
    try ParsedSourceArchive.write(
      entries,
      directories: mapped.directories,
      to: URL(fileURLWithPath: output)
    )
  }

  private func mappedSources() async throws -> MappedSources {
    var files: [MappedSourceFile] = []
    var directories: Set<String> = []
    for (inputPath, relativePath) in zip(input, path) {
      var isDirectory: ObjCBool = false
      guard unsafe FileManager.default.fileExists(
        atPath: inputPath,
        isDirectory: &isDirectory
      ) else {
        throw ValidationError("Cannot find input '\(inputPath)'.")
      }
      if isDirectory.boolValue {
        directories.insert(relativePath)
        let failures = await DirectoryWalker.walk(inputPath) { child, entry in
          let childPath = LexicalFilePath(relativePath)
            .appending(child).string
          if entry == .directory {
            directories.insert(childPath)
          } else if child.hasSuffix(".swift") {
            files.append(MappedSourceFile(
              inputPath: LexicalFilePath(inputPath).appending(child).string,
              relativePath: childPath
            ))
          }
          return .descend
        }
        guard failures.isEmpty else {
          let failure = failures[0]
          let failedPath = failure.relativePath.isEmpty
            ? inputPath
            : LexicalFilePath(inputPath)
            .appending(failure.relativePath).string
          throw ValidationError(
            "Cannot read the input directory '\(failedPath)': \(failure.reason)."
          )
        }
      } else if inputPath.hasSuffix(".swift") {
        files.append(MappedSourceFile(
          inputPath: inputPath,
          relativePath: relativePath
        ))
      }
    }
    return MappedSources(
      files: files.sorted { $0.relativePath < $1.relativePath },
      directories: directories
    )
  }
}

private struct MappedSources {
  let files: [MappedSourceFile]
  let directories: Set<String>
}

private struct MappedSourceFile: Sendable {
  let inputPath: String
  let relativePath: String
}
