import BylawsCore
import BylawsSemantics

struct ParsedRulesFile {
  let path: String
  let directory: String

  var imports: [ParsedImport] = []
  var codebases: [String: Codebase] = [:]
  var layerings: [String: Layering] = [:]
  var bindingNames: Set<String> = []
  var rules: [ParsedRule] = []
  var runtimeFunctions: [RuntimeFunctionDefinition] = []
  var runtimeBindings: [RuntimeGlobalBinding] = []
  var runtimeRuleBindings: [String] = []
  var diagnostics: [Diagnostic] = []
}

struct ParsedImport: Sendable {
  let moduleName: String
  let location: DeclarationLocation

  var isInterpretedSourceModule: Bool {
    PortableImportedModule(rawValue: moduleName) == nil
  }

  var requiresTargetDependency: Bool {
    PortableImportedModule(rawValue: moduleName) != .testing
  }
}

struct ParsedRule {
  let overrideReason: String?
  let id: String?
  let name: String

  let declaredEnforcement: Enforcement?

  let declaredHint: String?

  let location: DeclarationLocation
  let body: BodyExpression

  var isOverride: Bool { overrideReason != nil }
}

enum BodyExpression {
  case query(QueryExpression)
  case layeringCheck(codebase: String, layering: String)
  case folderLayout(codebase: String, pattern: String, folders: [String])
  case packageDependencies(codebase: String, ignoredTargets: [String])
  case dependencyStability(codebase: String, ignoredTargets: [String])
}

struct QueryExpression {
  let codebase: String
  let accessor: ParsedCall
  var filters: [ParsedCall] = []
  let check: Check
}

enum Check {
  case of(MatcherExpression)

  case matching(MatcherExpression)

  case outsidePaths([String])
}
