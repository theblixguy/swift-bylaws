import ArgumentParser
import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsRunner
import BylawsSemantics
import Foundation

struct RulesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "rules",
    abstract: "Lists the project's rules and their source files."
  )

  @Option(
    help: "Use this project root instead of resolving one from the working directory."
  )
  var root: String?

  @Option(
    name: .customLong("for"),
    help: "List the rules that apply to this path."
  )
  var path: String?

  @Option(
    help: "Run this rule and show the files and declarations kept or removed by its selection filters."
  )
  var explain: String?

  @Option(
    name: .customLong(InternalOptionName.swiftPackageModules.rawValue),
    help: ArgumentHelp(visibility: .hidden)
  )
  var swiftPackageModules: String?

  func run() async throws {
    let resolvedRoot: LexicalFilePath
    do {
      resolvedRoot = try ProjectRoot.resolve(explicit: root)
    } catch {
      try DiagnosticPrinter.printError(
        error.description,
        rulesFileRoot: LexicalFilePath.currentDirectory.string,
        format: .xcode
      )
      throw ExitCode(2)
    }
    let loaded = await RuleRunner.load(
      RuleRunConfiguration(
        root: resolvedRoot,
        parseCachePolicy: .environment(),
        swiftPackageModules: swiftPackageModules
      )
    )
    let rootPath = loaded.rootPath
    let program = loaded.program
    try DiagnosticPrinter.print(
      program.diagnostics,
      format: .xcode,
      rootPath: rootPath
    )
    guard program.errors.isEmpty else { throw ExitCode(2) }

    let listed: [RuleProgram.LoadedRule]
    do {
      listed = if let path {
        program.loadedRules(
          applyingTo: try Self.relative(path, toRoot: rootPath)
        )
      } else {
        program.loadedRules
      }
    } catch {
      try DiagnosticPrinter.printError(
        error.description,
        rulesFileRoot: rootPath,
        format: .xcode
      )
      throw ExitCode(2)
    }
    if let explain {
      let matches = listed.filter { $0.rule.id.rawValue == explain }
      guard !matches.isEmpty else {
        try DiagnosticPrinter.printError(
          "cannot find rule '\(explain)' in this scope. Run 'bylaws rules' to list rule IDs.",
          rulesFileRoot: rootPath,
          format: .xcode
        )
        throw ExitCode(2)
      }
      for loadedRule in matches {
        do {
          let inspection = try await loadedRule.rule.inspect()
          RuleInspectionPrinter.print(
            inspection,
            rule: loadedRule.rule,
            rootPath: rootPath
          )
        } catch {
          try DiagnosticPrinter.printError(
            error.description,
            rulesFileRoot: rootPath,
            format: .xcode
          )
          throw ExitCode(2)
        }
      }
      return
    }
    for loadedRule in listed {
      let rule = loadedRule.rule
      let enforcement = rule.enforcement == .advisory
        ? " (advisory)" : ""
      print("\(rule.id)\(enforcement)")
      print("  \(rule.name)")
      if let reason = loadedRule.scope?.overrideReason {
        print("  overrides the root rule: \(reason)")
      }
      print("  \(rule.location.filePath):\(rule.location.line)")
    }
  }

  static func relative(
    _ path: String,
    toRoot rootPath: String
  ) throws(PathOutsideRootError) -> String {
    let candidate = LexicalFilePath(path, relativeTo: .currentDirectory)
    guard let relative = candidate.relative(to: LexicalFilePath(rootPath))
    else {
      throw PathOutsideRootError(path: path, rootPath: rootPath)
    }
    return relative.string
  }
}

struct PathOutsideRootError: Error, CustomStringConvertible {
  let path: String
  let rootPath: String

  var description: String { "'\(path)' is outside '\(rootPath)'" }
}
