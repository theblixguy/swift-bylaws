import Foundation
import PackagePlugin

@main
struct BylawsBuildToolPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) throws -> [Command] {
    guard target is SourceModuleTarget else { return [] }

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
