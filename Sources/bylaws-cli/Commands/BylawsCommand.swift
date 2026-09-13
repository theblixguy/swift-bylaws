import ArgumentParser
import BylawsRunner

@main
struct BylawsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bylaws",
    abstract: "Checks a project against its architectural rules.",
    discussion: """
    Rules live in Bylaws.swift files at the project root and beside a
    module's Package.swift. The same rules run here, in CI and as test
    cases.
    """,
    version: BylawsVersion.current,
    subcommands: [LintCommand.self, RulesCommand.self, InitCommand.self],
    defaultSubcommand: LintCommand.self
  )
}
