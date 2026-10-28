import BylawsCore
import BylawsIndex
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import Foundation

extension LintRunner {
  static func collect(
    _ configuration: RuleRunConfiguration,
    testPackagePath: String?,
    testFilters: [String],
    skipTests: Bool,
    captureSources: Bool,
    directory: URL,
    previousTestReports: [SwiftTestingRuleReport] = []
  ) async throws -> Collection {
    var configuration = configuration
    if captureSources {
      configuration.changedPaths = []
      configuration.parseCachePolicy = .disabled
      await RuleRunner.discardCaches(under: configuration.root.string)
    }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let collector = SourceCapture.Collector()
    let activeCollector = captureSources ? collector : nil
    let purpose: RuleRunPurpose = if captureSources {
      .proposeCorrections
    } else {
      .checkOnly
    }
    return try await RuleRunPurpose.$current.withValue(purpose) {
      try await SourceCapture.$collector.withValue(activeCollector) {
        () async throws -> Collection in
        let ruleInputs: [SourceCapture.Record] = if captureSources {
          try await captureRuleInputs(configuration)
        } else {
          []
        }
        let testRun: SwiftPMTestRun? = if skipTests {
          nil
        } else {
          try await collectTestRules(
            configuration, testPackagePath: testPackagePath,
            testFilters: testFilters, directory: directory,
            isCorrection: captureSources
          )
        }
        if testRun != nil {
          configuration.changedPaths = []
          configuration.parseCachePolicy = .disabled
        }
        let builds = CorrectionIndexBuilds(
          directory: directory,
          testRun: testRun
        )
        let builder: ProjectIndexCache.IndexStoreBuilder? =
          if captureSources, !configuration.sourceOnly {
            .init { try await builds.buildIfNeeded(atRoot: $0) }
          } else {
            nil
          }
        return try await ProjectIndexCache.$indexStoreBuilder
          .withValue(builder) {
            let loaded = await RuleRunner.load(configuration)
            if loaded.program.ruleFileStatus != .missing,
               !loaded.program.errors.isEmpty
            {
              return Collection(
                result: try await RuleRunner.run(configuration, loaded: loaded),
                captures: ruleInputs + (testRun?.captures ?? []) +
                  (await collector.captured),
                protectedPaths: Set(loaded.program.ruleSourcePaths ?? []),
                testReports: []
              )
            }
            let testReports = try SwiftTestingRuleResults.reports(
              from: testRun, verifying: previousTestReports
            )
            let program = if loaded.program.ruleFileStatus == .missing,
                             !testReports.isEmpty
            {
              LoadedRuleProgram(
                rootPath: loaded.rootPath,
                program: RuleProgram(loadedRules: [], diagnostics: [])
              )
            } else {
              loaded
            }
            let testRules = try SwiftTestingRuleResults.collect(
              from: testReports, alongside: program.program.rules
            )
            let result = try await RuleRunner.run(
              configuration, loaded: program, testRules: testRules
            )
            let captures = ruleInputs + (testRun?.captures ?? [])
              + (await collector.captured)
            var protected = Set(loaded.program.ruleSourcePaths ?? [])
            protected.formUnion(ruleInputs.flatMap { $0.inputs.map(\.path) })
            protected.formUnion(testRun?.protectedSourcePaths ?? [])
            protected.formUnion(testReports.map(\.location.filePath))
            protected.formUnion(captures.flatMap(\.inputs).map(\.path).filter {
              ["Package.swift", "Bylaws.swift", "Bylaws.baseline.swift"]
                .contains(URL(fileURLWithPath: $0).lastPathComponent)
            })
            return Collection(
              result: result, captures: captures, protectedPaths: protected,
              testReports: testReports
            )
          }
      }
    }
  }

  private static func captureRuleInputs(
    _ configuration: RuleRunConfiguration
  ) async throws -> [SourceCapture.Record] {
    let root = configuration.root.string
    let discovered = try await SourceCapture.capture(SourceCapture.Scope(
      rootPath: root,
      selection: .sourceFiles(
        including: [
          "**/Bylaws.swift",
          "**/Bylaws.baseline.swift",
          "Package.swift",
        ],
        excluding: ["**/.git/**", "**/.build/**"],
        swiftPM: false, xcode: false
      )
    ))
    let explicit = configuration.ruleFilePaths.map(\.string)
      + [configuration.baseline].compactMap(\.self).map {
        LexicalFilePath($0, relativeTo: configuration.root).string
      }
    guard !explicit.isEmpty else { return [discovered] }
    return [discovered, try await SourceCapture.capture(SourceCapture.Scope(
      rootPath: root, selection: .paths(explicit)
    ))]
  }

  private static func collectTestRules(
    _ configuration: RuleRunConfiguration,
    testPackagePath: String?,
    testFilters: [String],
    directory: URL,
    isCorrection: Bool
  ) async throws -> SwiftPMTestRun? {
    let root = configuration.root.string
    let packageRoot = LexicalFilePath(
      testPackagePath ?? root,
      relativeTo: configuration.root
    )
    guard FileManager.default
      .fileExists(atPath: packageRoot.appending("Package.swift").string)
    else {
      if testPackagePath != nil || !testFilters.isEmpty {
        throw CaptureError(
          "cannot find Package.swift at '\(packageRoot.string)'; select a SwiftPM test package"
        )
      }
      return nil
    }
    do {
      return try await SwiftPMTestRunner.collect(
        atRoot: packageRoot.string, filters: testFilters,
        freshIndex: isCorrection && !configuration.sourceOnly,
        session: SwiftTestingRuleSession(
          id: UUID().uuidString, directory: directory.path, rootPath: root,
          isCorrection: isCorrection, sourceOnly: configuration.sourceOnly
        )
      )
    } catch SwiftPMTestRunnerError.noTestTargets {
      if !testFilters.isEmpty { throw SwiftPMTestRunnerError.noMatchingTests }
      return nil
    }
  }
}
