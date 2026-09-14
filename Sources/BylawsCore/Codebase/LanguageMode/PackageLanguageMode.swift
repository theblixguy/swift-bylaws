import BylawsPaths
import BylawsSemantics

struct PackageLanguageMode {
  let manifest: PackageManifest
  let directory: LexicalFilePath

  func mode(for path: LexicalFilePath) throws(CodebaseError)
    -> SwiftLanguageMode
  {
    let manifestPath = directory.appending("Package.swift").string
    if path.string == manifestPath {
      return SwiftLanguageMode(toolsVersion: manifest.toolsVersion)
    }
    guard let targets = manifest.targets.values else {
      throw .languageModeUnavailable(path: manifestPath)
    }
    var modes: Set<SwiftLanguageMode> = []
    var hasTarget = false
    for target in targets {
      let membership = contains(path, in: target)
      guard membership != false else { continue }
      modes.insert(try mode(for: target, at: manifestPath))
      hasTarget = hasTarget || membership == true
    }
    if !hasTarget { modes.insert(try defaultMode(at: manifestPath)) }
    guard modes.count == 1, let mode = modes.first else {
      throw .languageModeUnavailable(path: manifestPath)
    }
    return mode
  }

  private func mode(
    for target: PackageManifest.Target, at path: String
  ) throws(CodebaseError) -> SwiftLanguageMode {
    guard target.buildSettings.unresolvedValues.isEmpty else {
      throw .languageModeUnavailable(path: path)
    }
    var selected: SwiftLanguageMode?
    for setting in target.buildSettings.knownValues
      where setting.tool == .swift
    {
      switch setting.value {
      case let .swiftLanguageMode(written):
        guard setting.condition == nil, let mode = Self.mode(written) else {
          throw .languageModeUnavailable(path: path)
        }
        selected = mode
      case let .unsafeFlags(flags) where Self.hasModeFlag(flags):
        throw .languageModeUnavailable(path: path)
      default: break
      }
    }
    for setting in target.buildSettings.conditionalValues {
      switch setting.value {
      case .swiftLanguageMode:
        throw .languageModeUnavailable(path: path)
      case let .unsafeFlags(flags) where Self.hasModeFlag(flags):
        throw .languageModeUnavailable(path: path)
      default: break
      }
    }
    if let selected { return selected }
    return try defaultMode(at: path)
  }

  private func defaultMode(at path: String) throws(CodebaseError)
    -> SwiftLanguageMode
  {
    guard let written = manifest.swiftLanguageModes.values else {
      throw .languageModeUnavailable(path: path)
    }
    guard !written.isEmpty else {
      return SwiftLanguageMode(toolsVersion: manifest.toolsVersion)
    }
    let modes = written.compactMap(Self.mode)
    guard modes.count == written.count, let latest = modes.max(by: {
      $0.rawValue < $1.rawValue
    }) else { throw .languageModeUnavailable(path: path) }
    return latest
  }

  private func contains(
    _ path: LexicalFilePath,
    in target: PackageManifest.Target
  ) -> Bool? {
    if target.unresolvedValues
      .contains(where: { $0.field.hasSuffix(".path") })
    {
      return nil
    }
    let root = directory.appending(target.sourceDirectory)
    guard root.contains(path) else { return false }
    if target.excludedPaths.knownValues.contains(where: {
      root.appending($0).contains(path)
    }) { return false }
    if case let .explicit(paths) = target.sources,
       !paths.knownValues
       .contains(where: { root.appending($0).contains(path) })
    {
      return paths.isComplete ? false : nil
    }
    return target.excludedPaths.isComplete ? true : nil
  }

  private static func hasModeFlag(_ flags: [String]) -> Bool {
    flags.contains {
      $0 == "-swift-version" || $0.hasPrefix("-swift-version=") || $0
        .hasPrefix("@")
    }
  }

  static func mode(_ value: String) -> SwiftLanguageMode? {
    switch value {
    case "v4", "v4_2", "4", "4.0", "4.2": .v4
    case "v5", "5", "5.0": .v5
    case "v6", "6", "6.0": .v6
    default: nil
    }
  }
}
