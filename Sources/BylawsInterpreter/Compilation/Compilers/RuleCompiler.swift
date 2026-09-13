import BylawsCore
import BylawsSemantics

enum RuleCompiler {
  typealias FindingsBody = @Sendable () async throws -> Rule.Findings
  private typealias BodyFactory =
    @Sendable (_ excludedSubtrees: [String]) -> FindingsBody

  struct Header {
    let name: String
    let enforcement: Enforcement
    let hint: String?
  }

  struct Compiled: Sendable {
    fileprivate let make: @Sendable (_ excludedSubtrees: [String]) -> Rule

    func rule(excludingSubtrees subtrees: [String] = []) -> Rule {
      make(subtrees)
    }
  }

  static func compile(
    _ parsed: ParsedRule,
    as header: Header,
    in file: ParsedRulesFile
  ) -> Result<Compiled, Diagnostic> {
    compileBody(parsed, in: file).map { body in
      let id = Rule.ID(parsed.id ?? header.name)
      let location = parsed.location
      return Compiled { subtrees in
        Rule(
          id,
          header.name,
          enforcement: header.enforcement,
          hint: header.hint,
          location: location,
          body: body(subtrees)
        )
      }
    }
  }

  private static func compileBody(
    _ parsed: ParsedRule,
    in file: ParsedRulesFile
  ) -> Result<BodyFactory, Diagnostic> {
    switch parsed.body {
    case let .folderLayout(codebaseName, pattern, folders):
      guard let codebase = file.codebases[codebaseName] else {
        return .failure(unknownCodebase(codebaseName, at: parsed.location))
      }
      let location = parsed.location
      return .success { subtrees in
        {
          let findings = try await codebase.checkFolderLayout(
            matching: pattern,
            containing: folders
          )
          .findings(reportedAt: location)
          guard !subtrees.isEmpty else { return findings }
          let excluded = try ExcludedSubtrees(
            subtrees: subtrees,
            under: [codebase.resolvedRootPath()]
          )
          return excluded.filteringOffenders(from: findings)
        }
      }

    case let .dependencyStability(codebaseName, ignoredTargets):
      guard let codebase = file.codebases[codebaseName] else {
        return .failure(unknownCodebase(codebaseName, at: parsed.location))
      }
      let ruleLocation = parsed.location
      return .success { _ in
        {
          try await codebase.checkDependencyStability(ignoring: ignoredTargets)
            .findings(reportedAt: ruleLocation)
        }
      }

    case let .packageDependencies(codebaseName, ignoredTargets):
      guard let codebase = file.codebases[codebaseName] else {
        return .failure(unknownCodebase(codebaseName, at: parsed.location))
      }
      let ruleLocation = parsed.location
      return .success { _ in
        {
          try await codebase.checkPackageDependencies(ignoring: ignoredTargets)
            .findings(reportedAt: ruleLocation)
        }
      }

    case let .layeringCheck(codebaseName, layeringName):
      guard let codebase = file.codebases[codebaseName] else {
        return .failure(unknownCodebase(codebaseName, at: parsed.location))
      }
      guard let layering = file.layerings[layeringName] else {
        return .failure(
          .error(
            "'\(layeringName)' is not a layering this file declares",
            at: parsed.location
          )
        )
      }
      let ruleLocation = parsed.location
      return .success { subtrees in
        {
          let findings = try await codebase.checkLayering(layering)
            .findings(reportedAt: ruleLocation)
          guard !subtrees.isEmpty else { return findings }
          let excluded = try ExcludedSubtrees(
            subtrees: subtrees,
            under: [codebase.resolvedRootPath()]
          )
          return excluded.filteringOffenders(from: findings)
        }
      }

    case let .query(query):
      guard let codebase = file.codebases[query.codebase] else {
        return .failure(unknownCodebase(query.codebase, at: parsed.location))
      }
      return QueryCompiler.compile(query, over: codebase).map { factory in
        { subtrees in
          let body = factory(subtrees)
          return { try await Rule.Findings(violations: body()) }
        }
      }
    }
  }

  private static func unknownCodebase(
    _ name: String,
    at location: DeclarationLocation
  ) -> Diagnostic {
    .error(
      "'\(name)' is not a codebase this file declares",
      at: location,
      hint: "declare it with 'let \(name) = Codebase(including: [\"Sources/**\"])'"
    )
  }
}

extension ParsedRule {
  func header(inheriting root: ParsedRule? = nil) -> RuleCompiler.Header {
    RuleCompiler.Header(
      name: root?.name ?? name,
      enforcement: declaredEnforcement
        ?? root?.declaredEnforcement
        ?? .enforced,
      hint: declaredHint ?? root?.declaredHint
    )
  }
}
