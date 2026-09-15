import ArgumentParser
import BylawsRunner

@main
struct BylawsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bylaws",
    abstract: "Checks a project against its architectural rules.",
    discussion: """
    Keep project-wide rules in the root Bylaws.swift and add rules in
    subfolders where needed. You can run the same rules here, in CI
    or from a test target.
    """,
    version: BylawsVersion.current,
    subcommands: [LintCommand.self, RulesCommand.self, InitCommand.self],
    defaultSubcommand: LintCommand.self
  )
}
