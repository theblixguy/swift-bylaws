import Foundation
import PackagePlugin

@main
struct BylawsBuildToolPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) throws -> [Command] {
    guard target is SourceModuleTarget else { return [] }
    let environment = ProcessInfo.processInfo.environment
    if environment["BYLAWS_SWIFT_TESTING_RULE_SESSION"] != nil
      || environment["BYLAWS_CORRECTION_ACTIVE"] == "1"
    {
      return []
    }

    let index = try PackageModuleIndex(package: context.package)
    let indexURL = context.pluginWorkDirectoryURL
      .appendingPathComponent("package-modules.json")
    try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)

    return [
      .prebuildCommand(
        displayName: "Check Bylaws rules",
        executable: try context.tool(named: "bylaws-cli").url,
        arguments: [
          "lint",
          "--root", context.package.directoryURL.path,
          "--swift-package-modules", indexURL.path,
          "--source-only",
          "--skip-tests",
          "--cache-path", context.pluginWorkDirectoryURL
            .appendingPathComponent("Cache").path,
          "--quiet",
        ],
        outputFilesDirectory: context.pluginWorkDirectoryURL
          .appendingPathComponent("Output")
      ),
    ]
  }
}
