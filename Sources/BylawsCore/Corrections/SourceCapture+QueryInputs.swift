import BylawsPaths
import Foundation

extension SourceCapture {
  static func record(
    _ inputs: [Input], for codebase: Codebase, rootPath: String,
    directories: DirectoryInput? = nil
  ) async throws(CodebaseError) {
    guard isEnabled else { return }
    if case .sources = codebase.root.strategy { return }
    try await save(Record(
      sessionID: ProcessInfo.processInfo
        .environment["BYLAWS_SOURCE_CAPTURE_ID"],
      scope: Scope(
        rootPath: rootPath,
        selection: .paths(inputs.map(\.path))
      ),
      inputs: inputs.sorted { $0.path < $1.path },
      rootSearchPath: rootSearchPath(for: codebase),
      directories: directories
    ))
  }

  static func failed(
    _ queryError: CodebaseError, for codebase: Codebase
  ) async -> CodebaseError {
    do {
      try await recordFailure(queryError, for: codebase)
    } catch let captureError {
      return captureError
    }
    return queryError
  }

  package static func recordFailure(
    _ error: some Error, for codebase: Codebase
  ) async throws(CodebaseError) {
    guard isEnabled else { return }
    let rootPath: String
    switch codebase.root.strategy {
    case let .directory(path):
      rootPath = LexicalFilePath(path, relativeTo: .currentDirectory).string
    case let .automatic(path):
      rootPath = LexicalFilePath(path, relativeTo: .currentDirectory)
        .removingLastComponent().string
    case .sources:
      return
    }
    try await save(Record(
      sessionID: ProcessInfo.processInfo
        .environment["BYLAWS_SOURCE_CAPTURE_ID"],
      scope: Scope(
        rootPath: rootPath, selection: .paths([])
      ),
      inputs: [], unavailableReason: String(describing: error)
    ))
  }

  static func rootSearchPath(for codebase: Codebase) -> String? {
    guard case let .automatic(path) = codebase.root.strategy else { return nil }
    return LexicalFilePath(path, relativeTo: .currentDirectory)
      .removingLastComponent().string
  }

  static func save(
    _ record: Record,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) async throws(CodebaseError) {
    do {
      try await store(record, environment: environment)
    } catch {
      let storageReason = "cannot save the source capture: \(error)"
      let reason = if let queryReason = record.unavailableReason {
        "\(queryReason)\n\(storageReason)"
      } else {
        storageReason
      }
      throw .unreadable(failures: [.init(
        path: record.scope.rootPath,
        reason: reason
      )])
    }
  }

  static func validate(
    _ input: DirectoryInput, under rootPath: String
  ) async throws {
    let changed = switch input {
    case let .folderLayout(pattern, paths):
      Codebase.layoutDirectoryInput(
        try await Codebase.readLayoutDirectories(
          matching: Glob(pattern), rootPath: rootPath
        ),
        matching: Glob(pattern)
      ) != paths
    case let .xcodeProjects(projects):
      try FileManager.default.contentsOfDirectory(atPath: rootPath)
        .filter { $0.hasSuffix(".xcodeproj") }.sorted() != projects
    }
    guard !changed else {
      throw CaptureError(
        "source directories changed under '\(rootPath)'; run the command again"
      )
    }
  }
}
