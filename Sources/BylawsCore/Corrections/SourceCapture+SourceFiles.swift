import BylawsPaths
package import BylawsSemantics
import Foundation

extension SourceCapture {
  package static func begin(_ codebase: Codebase) async throws(CodebaseError)
    -> Record?
  {
    guard isEnabled else { return nil }
    if case .sources = codebase.root.strategy { return nil }
    let projects: Codebase.LanguageMode.Projects = switch codebase
      .swiftLanguageMode
    {
    case let .automatic(projects): projects
    case .v4, .v5, .v6: []
    }
    let scope = Scope(
      rootPath: try codebase.resolvedRootPath(),
      selection: .sourceFiles(
        including: codebase.including.map(\.pattern),
        excluding: codebase.excluding.map(\.pattern),
        swiftPM: projects.contains(.swiftPM),
        xcode: projects.contains(.xcode)
      )
    )
    do {
      return try await capture(
        scope, rootSearchPath: rootSearchPath(for: codebase)
      )
    } catch let error as CodebaseError {
      throw error
    } catch {
      throw .unreadable(failures: [
        .init(path: scope.rootPath, reason: String(describing: error)),
      ])
    }
  }

  package static func finish(
    _ record: Record?,
    files: [SourceFile],
    rootPath: String,
    consumedInputs: [Input],
    xcodeProjects: [String]?
  ) async throws(CodebaseError) {
    guard let record else { return }
    guard rootPath == record.scope.rootPath,
          record.sourcePaths == files.map(\.path).sorted()
    else {
      throw .unreadable(failures: [.init(
        path: record.scope.rootPath,
        reason: "the source changed during collection; run the command again"
      )])
    }
    let inputs = Dictionary(uniqueKeysWithValues: record.inputs
      .compactMap { input in
        input.digest.map { (input.path, $0) }
      })
    for file in files {
      guard inputs[file.path] == digest(Data(file.sourceText.utf8)) else {
        throw .unreadable(failures: [.init(
          path: file.path,
          reason: "the source changed during collection; run the command again"
        )])
      }
    }
    try await save(record)
    if !consumedInputs.isEmpty || xcodeProjects != nil {
      try await save(Record(
        sessionID: record.sessionID,
        scope: Scope(
          rootPath: record.scope.rootPath,
          selection: .paths(consumedInputs.map(\.path))
        ),
        inputs: consumedInputs.sorted { $0.path < $1.path },
        rootSearchPath: record.rootSearchPath,
        directories: xcodeProjects.map(DirectoryInput.xcodeProjects)
      ))
    }
  }

  package static func capture(
    _ scope: Scope, sessionID: String? = nil,
    rootSearchPath: String? = nil
  ) async throws -> Record {
    let paths = try await paths(in: scope)
    let inputs = try paths.paths.map { path -> Input in
      if !FileManager.default.fileExists(atPath: path) {
        return Input(path: path, digest: nil)
      }
      return Input(
        path: path,
        digest: digest(try Data(contentsOf: URL(fileURLWithPath: path)))
      )
    }
    return Record(
      sessionID: sessionID ?? ProcessInfo.processInfo
        .environment["BYLAWS_SOURCE_CAPTURE_ID"],
      scope: scope,
      inputs: inputs,
      sourcePaths: paths.sourcePaths,
      rootSearchPath: rootSearchPath
    )
  }

  private static func paths(in scope: Scope) async throws
    -> (paths: [String], sourcePaths: [String]?)
  {
    switch scope.selection {
    case let .paths(paths):
      return (Array(Set(paths)).sorted(), nil)
    case let .sourceFiles(including, excluding, swiftPM, xcode):
      let root = LexicalFilePath(scope.rootPath)
      let (sourcePaths, failures) = await SourceFileDiscovery.paths(
        under: scope.rootPath,
        including: including.map { Glob($0) },
        excluding: excluding.map { Glob($0) }
      )
      guard failures.isEmpty else {
        throw CodebaseError.unreadable(failures: failures)
      }
      var paths = Set(sourcePaths)
      if swiftPM {
        for path in sourcePaths {
          var directory = LexicalFilePath(path).removingLastComponent()
          while root.contains(directory) {
            paths.insert(directory.appending("Package.swift").string)
            if directory == root { break }
            directory = directory.removingLastComponent()
          }
        }
        paths.insert(root.appending("Package.swift").string)
        paths.formUnion([
          "Package.resolved",
          ".swiftpm/configuration/mirrors.json",
          ".swiftpm/configuration/registries.json",
        ].map { root.appending($0).string })
      }
      if xcode {
        let projects = try FileManager.default
          .contentsOfDirectory(atPath: scope.rootPath)
          .filter { $0.hasSuffix(".xcodeproj") }
        paths.formUnion(projects.map {
          root.appending($0).appending("project.pbxproj").string
        })
      }
      return (paths.sorted(), sourcePaths.sorted())
    }
  }
}
