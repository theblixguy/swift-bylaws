import Foundation
import PackagePlugin

@main
struct BylawsPlugin: CommandPlugin {
  func performCommand(
    context: PluginContext,
    arguments: [String]
  ) async throws {
    let index = try PackageModuleIndex(package: context.package)
    let indexURL = context.pluginWorkDirectoryURL
      .appendingPathComponent("package-modules.json")
    try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)

    let process = Process()
    process.executableURL = try context.tool(named: "bylaws-cli").url
    process.arguments = [
      CommandName.lint.rawValue,
      OptionName.swiftPackageModules.rawValue,
      indexURL.path,
    ] + arguments
    process.currentDirectoryURL = context.package.directoryURL
    try process.run()
    process.waitUntilExit()

    guard process.terminationReason == .exit,
          process.terminationStatus == 0
    else {
      throw PluginFailure(
        status: process.terminationStatus,
        reason: process.terminationReason
      )
    }
  }
}

private enum CommandName: String {
  case lint
}

private enum OptionName: String {
  case swiftPackageModules = "--swift-package-modules"
}

private struct PluginFailure: Error, CustomStringConvertible {
  let status: Int32
  let reason: Process.TerminationReason

  var description: String {
    "bylaws ended with \(reason == .exit ? "status" : "signal") \(status)"
  }
}
