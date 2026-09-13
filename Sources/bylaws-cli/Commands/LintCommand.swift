import ArgumentParser
import BylawsCore
import BylawsPaths
import BylawsRunner
import Foundation

struct LintCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lint",
    abstract: "Discovers rules files and checks the codebase.",
    discussion: """
    Exits with status code 0 when the rules hold, status code 1 on violations \
    and status code 2 when the rules files do not load.
    """
  )

  @Option(
    help: "Use this project root instead of resolving one from the working directory."
  )
  var root: String?

  @Option(
    parsing: .upToNextOption,
    help: "Rules files to load instead of discovering them."
  )
  var rules: [String] = []

  @Option(parsing: .upToNextOption, help: "Run the rules with these IDs.")
  var only: [String] = []

  @Option(parsing: .upToNextOption, help: "Skip the rules with these IDs.")
  var skip: [String] = []

  @Flag(help: "Fail on advisory violations too.")
  var strict = false

  @Flag(help: "Reject compiler-index queries that need a completed build.")
  var sourceOnly = false

  @Option(help: "Choose xcode, github, json or sarif output.")
  var format = OutputFormat.xcode

  @Option(
    name: .customLong("report-path"),
    parsing: .upToNextOption,
    help: "Report findings in these project-relative or absolute paths."
  )
  var reportPaths: [String] = []

  @Flag(help: "Print violations without the summary line.")
  var quiet = false

  @Option(
    help: """
    Use this recorded baseline file instead of discovered \
    Bylaws.baseline.swift files. Known violations do not fail the run. \
    Stale entries do.
    """
  )
  var baseline: String?

  @Option(help: "Record the current violations as a baseline at this path.")
  var recordBaseline: String?

  @Flag(help: "Read and write the parse cache that test runs use.")
  var cache = false

  @Option(
    help: """
    Keep the parse cache in this directory instead of the user's caches \
    directory. This option also enables --cache.
    """
  )
  var cachePath: String?

  @Option(
    name: .customLong(InternalOptionName.swiftPackageModules.rawValue),
    help: ArgumentHelp(visibility: .hidden)
  )
  var swiftPackageModules: String?

  func run() async throws {
    let rootPath: LexicalFilePath
    do {
      rootPath = try ProjectRoot.resolve(
        explicit: root,
        hasExplicitRuleFiles: !rules.isEmpty
      )
    } catch {
      try DiagnosticPrinter.printError(
        error.description,
        rulesFileRoot: LexicalFilePath.currentDirectory.string,
        format: format
      )
      throw ExitCode(2)
    }
    if recordBaseline != nil,
       !only.isEmpty || !skip.isEmpty || !reportPaths.isEmpty
    {
      try DiagnosticPrinter.printError(
        "--record-baseline cannot be combined with --only, --skip or --report-path",
        rulesFileRoot: rootPath.string,
        format: format
      )
      throw ExitCode(2)
    }

    let result = try await RuleRunner.run(
      RuleRunConfiguration(
        root: rootPath,
        ruleFilePaths: rules.map {
          LexicalFilePath($0, relativeTo: .currentDirectory)
        },
        only: only,
        skip: skip,
        strict: strict,
        sourceOnly: sourceOnly,
        baseline: baseline,
        reportPaths: reportPaths,
        parseCachePolicy: parseCachePolicy,
        swiftPackageModules: swiftPackageModules
      )
    )

    if result.outcome == .invalidRules
      || result.outcome == .notConfigured
    {
      try DiagnosticPrinter.print(
        result.diagnostics,
        format: format,
        rootPath: result.rootPath
      )
      throw ExitCode(2)
    }

    if let recordBaseline {
      do {
        try record(result.baselineEntries, at: recordBaseline)
      } catch {
        try DiagnosticPrinter.printWriteFailure(
          error,
          writing: "the baseline file '\(recordBaseline)'",
          rulesFileRoot: result.rootPath,
          format: format
        )
        throw ExitCode(2)
      }
      return
    }

    let output = try ReportRenderer.render(
      result.document,
      format: format,
      quiet: quiet,
      rootPath: result.rootPath
    )
    if !output.isEmpty {
      print(output)
    }

    if result.outcome == .violations {
      throw ExitCode(1)
    }
  }

  private var parseCachePolicy: ParseCachePolicy {
    if let cachePath {
      return .enabled(
        directory: URL(fileURLWithPath: cachePath),
        cachesTemporaryRoots: true
      )
    }
    if cache {
      return .defaultEnabled(cachesTemporaryRoots: true)
    }
    return .disabled
  }

  private func record(
    _ entries: Set<Baseline.Entry>,
    at path: String
  ) throws {
    let content = BaselineFile.render(
      name: "project",
      entries: Array(entries)
    )
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    if !quiet {
      let count = entries.count == 1 ? "1 entry" : "\(entries.count) entries"
      print("Recorded \(count) at \(path).")
    }
  }
}

enum InternalOptionName: String {
  case swiftPackageModules = "swift-package-modules"
}
