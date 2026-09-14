import BylawsPaths
import BylawsSemantics
import Foundation

struct SourceLanguageModes {
  let root: LexicalFilePath
  let overlay: SourceOverlay
  let sources: [String: String]?
  let languageMode: Codebase.LanguageMode
  private var packages: [LexicalFilePath: PackageLanguageMode] = [:]
  private var searched: Set<LexicalFilePath> = []
  private var xcodeMode: SwiftLanguageMode?

  init(
    root: String,
    overlay: SourceOverlay = .empty,
    sources: [String: String]? = nil,
    languageMode: Codebase.LanguageMode = .automatic(.swiftPM)
  ) {
    self.root = LexicalFilePath(root)
    self.overlay = overlay
    self.sources = sources
    self.languageMode = languageMode
  }

  mutating func mode(for path: String) throws(CodebaseError)
    -> SwiftLanguageMode
  {
    switch languageMode {
    case .v4: return .v4
    case .v5: return .v5
    case .v6: return .v6
    case let .automatic(projects):
      if projects.contains(.swiftPM), let mode = try packageMode(for: path) {
        return mode
      }
      guard projects.contains(.xcode), sources == nil else { return .v6 }
      return try xcodeLanguageMode()
    }
  }

  private mutating func packageMode(for path: String) throws(CodebaseError)
    -> SwiftLanguageMode?
  {
    let file = LexicalFilePath(path)
    var directory = file.removingLastComponent()
    while root.contains(directory) {
      if searched.insert(directory).inserted {
        let path = directory.appending("Package.swift").string
        let source: String?
        if let sources {
          source = sources[path]
        } else if let overlaid = overlay.text(forFileAt: path) {
          source = overlaid
        } else if FileManager.default.fileExists(atPath: path) {
          do {
            source = try FileCollector.readSource(atPath: path)
          } catch {
            throw .unreadable(failures: [.init(
              path: path,
              reason: error.description
            )])
          }
        } else {
          source = nil
        }
        if let source {
          let manifest = PackageManifest(source: source)
          let mode = SwiftLanguageMode(toolsVersion: manifest.toolsVersion)
          do {
            _ = try FileCollector.collect(
              source: source, path: path,
              swiftLanguageMode: mode
            )
          } catch {
            switch error {
            case let .didNotParse(diagnostics):
              throw .didNotParse(diagnostics: diagnostics)
            case let .unreadable(path, reason):
              throw .unreadable(failures: [.init(path: path, reason: reason)])
            }
          }
          if manifest.toolsVersion != nil || manifest.name != nil || !manifest
            .targets.knownValues.isEmpty
          {
            packages[directory] = PackageLanguageMode(
              manifest: manifest,
              directory: directory
            )
          }
        }
      }
      if let package = packages[directory] {
        return try package.mode(for: file)
      }
      guard directory != root else { break }
      directory = directory.removingLastComponent()
    }
    return nil
  }

  private mutating func xcodeLanguageMode() throws(CodebaseError)
    -> SwiftLanguageMode
  {
    if let xcodeMode { return xcodeMode }
    let names: [String]
    do {
      names = try FileManager.default.contentsOfDirectory(atPath: root.string)
    } catch {
      throw .unreadable(failures: [.init(
        path: root.string,
        reason: error.reportableDescription
      )])
    }
    let projects = names.filter { $0.hasSuffix(".xcodeproj") }.sorted()
    var modes: Set<SwiftLanguageMode> = []
    for project in projects {
      let path = root.appending(project).appending("project.pbxproj").string
      let source: String
      do {
        source = if let overlaid = overlay.text(forFileAt: path) { overlaid }
        else { try FileCollector.readSource(atPath: path) }
      } catch {
        throw .unreadable(failures: [.init(
          path: path,
          reason: error.description
        )])
      }
      modes.insert(try XcodeLanguageMode.read(source: source, path: path))
    }
    guard modes.count <= 1
    else { throw .languageModeUnavailable(path: root.string) }
    let mode = modes.first ?? .v6
    xcodeMode = mode
    return mode
  }
}
