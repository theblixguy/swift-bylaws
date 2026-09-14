import BylawsSemantics
import Foundation

enum XcodeLanguageMode {
  static func read(
    source: String,
    path: String
  ) throws(CodebaseError) -> SwiftLanguageMode {
    guard let plist = unsafe try? PropertyListSerialization.propertyList(
      from: Data(source.utf8), format: nil
    ) as? [String: Any],
      let objects = plist["objects"] as? [String: [String: Any]],
      let rootID = plist["rootObject"] as? String,
      let project = objects[rootID],
      let targets = project["targets"] as? [String],
      let projectConfigurations = configurations(of: project, in: objects)
    else { throw .languageModeUnavailable(path: path) }

    var modes: Set<SwiftLanguageMode> = []
    for id in targets {
      guard let target = objects[id],
            target["isa"] as? String == "PBXNativeTarget" else { continue }
      guard let configurations = configurations(of: target, in: objects) else {
        throw .languageModeUnavailable(path: path)
      }
      for configuration in configurations {
        let name = configuration["name"] as? String
        let inherited = projectConfigurations
          .first { $0["name"] as? String == name }
        guard configuration["baseConfigurationReference"] == nil,
              inherited?["baseConfigurationReference"] == nil,
              let settings = configuration["buildSettings"] as? [String: Any],
              let projectSettings =
              inherited?["buildSettings"] as? [String: Any],
              !hasUnresolvedMode(settings),
              !hasUnresolvedMode(projectSettings),
              let value = settings["SWIFT_VERSION"] as? String
              ?? projectSettings["SWIFT_VERSION"] as? String,
              let mode = PackageLanguageMode.mode(value)
        else { throw .languageModeUnavailable(path: path) }
        modes.insert(mode)
      }
    }
    guard modes.count == 1, let mode = modes.first else {
      throw .languageModeUnavailable(path: path)
    }
    return mode
  }

  private static func configurations(
    of object: [String: Any], in objects: [String: [String: Any]]
  ) -> [[String: Any]]? {
    guard let listID = object["buildConfigurationList"] as? String,
          let ids = objects[listID]?["buildConfigurations"] as? [String]
    else { return nil }
    let configurations = ids.compactMap { objects[$0] }
    return configurations.count == ids.count && !configurations
      .isEmpty ? configurations : nil
  }

  private static func hasUnresolvedMode(_ settings: [String: Any]) -> Bool {
    if settings.keys
      .contains(where: { $0.hasPrefix("SWIFT_VERSION[") }) { return true }
    for (key, value) in settings where key.hasPrefix("OTHER_SWIFT_FLAGS") {
      let flags: String
      if let value = value as? String { flags = value }
      else if let values = value as? [String] {
        flags = values.joined(separator: " ")
      } else { return true }
      if flags.contains("-swift-version") || flags.contains("$(") || flags
        .contains("${") || flags.contains("@")
      {
        return true
      }
    }
    return false
  }
}
