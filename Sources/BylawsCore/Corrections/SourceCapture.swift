import BylawsPaths
import Crypto
package import Foundation

package enum SourceCapture {
  package struct Scope: Sendable, Hashable, Codable {
    package enum Selection: Sendable, Hashable, Codable {
      case sourceFiles(
        including: [String], excluding: [String], swiftPM: Bool, xcode: Bool
      )
      case paths([String])
    }

    package let rootPath: String
    package let selection: Selection

    package init(rootPath: String, selection: Selection) {
      self.rootPath = rootPath
      self.selection = selection
    }
  }

  package struct Input: Sendable, Hashable, Codable {
    package let path: String
    package let digest: String?
  }

  package enum DirectoryInput: Sendable, Hashable, Codable {
    case folderLayout(pattern: String, paths: [String])
    case xcodeProjects([String])
  }

  package struct Record: Sendable, Hashable, Codable {
    package let sessionID: String?
    package let scope: Scope
    package let inputs: [Input]
    package let sourcePaths: [String]?
    package let rootSearchPath: String?
    package let directories: DirectoryInput?
    package let unavailableReason: String?

    package init(
      sessionID: String?, scope: Scope, inputs: [Input],
      sourcePaths: [String]? = nil, rootSearchPath: String? = nil,
      directories: DirectoryInput? = nil, unavailableReason: String? = nil
    ) {
      self.sessionID = sessionID
      self.scope = scope
      self.inputs = inputs
      self.sourcePaths = sourcePaths
      self.rootSearchPath = rootSearchPath
      self.directories = directories
      self.unavailableReason = unavailableReason
    }
  }

  package actor Collector {
    private var records: Set<Record> = []

    package init() {}

    package func record(_ value: Record) {
      records.insert(value)
    }

    package var captured: [Record] {
      records.sorted { $0.scope.rootPath < $1.scope.rootPath }
    }
  }

  @TaskLocal package static var collector: Collector?

  package static var isEnabled: Bool {
    collector != nil
      || ProcessInfo.processInfo
      .environment["BYLAWS_SOURCE_CAPTURE_DIRECTORY"] != nil
  }

  package static func store(
    _ record: Record,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async throws {
    await collector?.record(record)
    guard let directory = environment["BYLAWS_SOURCE_CAPTURE_DIRECTORY"] else {
      return
    }
    guard record.sessionID != nil else {
      throw CaptureError("the source capture session is missing")
    }
    let path = URL(fileURLWithPath: directory)
      .appendingPathComponent(UUID().uuidString + ".json")
    try JSONEncoder().encode(record).write(to: path, options: .atomic)
  }

  package static func validate(_ records: [Record]) async throws {
    for record in records {
      if let reason = record.unavailableReason {
        throw CaptureError(
          "a source query failed. Run the command again before applying corrections.\n\(reason)"
        )
      }
    }
    var roots: Set<String> = []
    var inputsByPath: [String: Input] = [:]
    for record in records {
      if roots.insert(record.scope.rootPath).inserted {
        do {
          _ = try Codebase(root: .directory(record.scope.rootPath))
            .resolvedRootPath()
        } catch {
          throw CaptureError(
            "the codebase root changed at '\(record.scope.rootPath)'; run the command again"
          )
        }
      }
      for input in record.inputs {
        if let previous = inputsByPath[input.path], previous != input {
          throw CaptureError("source snapshots disagree at '\(input.path)'")
        }
        inputsByPath[input.path] = input
      }
      let current = try await capture(record.scope)
      guard current.inputs == record.inputs,
            record.sourcePaths == nil || current.sourcePaths == record
              .sourcePaths
      else {
        throw CaptureError(
          "source inputs changed under '\(record.scope.rootPath)'; run the command again"
        )
      }
      if let searchPath = record.rootSearchPath {
        let root = try Codebase.automaticRoot(at: LexicalFilePath(searchPath))
        guard root == record.scope.rootPath else {
          throw CaptureError(
            "the codebase root changed above '\(searchPath)'; run the command again"
          )
        }
      }
      if let directories = record.directories {
        try await validate(directories, under: record.scope.rootPath)
      }
    }
  }

  package static func digest(_ data: Data) -> String {
    let digits = Array("0123456789abcdef".utf8)
    let bytes = SHA256.hash(data: data).flatMap {
      [digits[Int($0 >> 4)], digits[Int($0 & 15)]]
    }
    return String(decoding: bytes, as: UTF8.self)
  }
}

package struct CaptureError: Error, CustomStringConvertible {
  package let description: String

  package init(_ description: String) {
    self.description = description
  }
}
