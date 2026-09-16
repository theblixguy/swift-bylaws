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
    help: "Rules files to load, relative to the project root, instead of discovering them."
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
    help: "Write the report to this file instead of standard output. Relative paths use the working directory."
  )
  var output: String?

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
    help: """
    Set the soft disk-cache target using whole bytes or a case-insensitive \
    B, KB, MB, GB, KiB, MiB or GiB suffix (for example, 500MB). This option \
    takes a value and enables caching, with zero disabling the disk cache. \
    The default target is 1GB.
    """
  )
  var cacheSize: CacheSize?

  @Option(
    help: ArgumentHelp(
      """
      Set the memory budget for retained query selections using whole bytes \
      or a case-insensitive B, KB, MB, GB, KiB, MiB or GiB suffix (for example, \
      32MiB). This option takes a value, with zero disabling selection reuse. \
      The default budget is 64MiB.
      """,
      valueName: "size"
    ),
    transform: { value in
      guard let size = CacheSize(argument: value) else {
        throw ValidationError(
          "Size must be a non-negative whole number of bytes or use B, KB, MB, GB, KiB, MiB or GiB, within the supported integer range."
        )
      }
      return UInt(size.bytes)
    }
  )
  var selectionCacheSize: UInt = SelectionCache.defaultBudget

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
      try reportError(
        error.description,
        rootPath: LexicalFilePath.currentDirectory.string
      )
      throw ExitCode(2)
    }
    if recordBaseline != nil,
       !only.isEmpty || !skip.isEmpty || !reportPaths.isEmpty
    {
      try reportError(
        "--record-baseline cannot be combined with --only, --skip or --report-path",
        rootPath: rootPath.string
      )
      throw ExitCode(2)
    }
    if recordBaseline != nil, output != nil {
      try reportError(
        "--record-baseline cannot be combined with --output. Run each command separately.",
        rootPath: rootPath.string
      )
      throw ExitCode(2)
    }

    let result = try await RuleRunner.run(
      RuleRunConfiguration(
        root: rootPath,
        ruleFilePaths: rules.map {
          LexicalFilePath($0, relativeTo: rootPath)
        },
        only: only,
        skip: skip,
        strict: strict,
        sourceOnly: sourceOnly,
        baseline: baseline
          .map { LexicalFilePath($0, relativeTo: rootPath).string },
        reportPaths: reportPaths,
        parseCachePolicy: parseCachePolicy,
        selectionCacheBudget: selectionCacheSize,
        swiftPackageModules: swiftPackageModules
      )
    )

    if result.outcome == .invalidRules
      || result.outcome == .notConfigured
    {
      try writeReport(result.document, rootPath: result.rootPath, quiet: true)
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

    try writeReport(result.document, rootPath: result.rootPath, quiet: quiet)

    if result.outcome == .violations {
      throw ExitCode(1)
    }
  }

  private var parseCachePolicy: ParseCachePolicy {
    if cache || cachePath != nil || cacheSize != nil {
      return .configured(ParseCacheConfiguration(
        directory: cachePath.map { URL(fileURLWithPath: $0) },
        budget: cacheSize?.bytes ?? ParseCacheConfiguration.defaultBudget
      ))
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
