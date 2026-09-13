import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func checkMember(
    _ name: SupportedAPI.Member,
    _ value: RuntimeCheckValue
  ) -> RuntimeValue? {
    switch value {
    case let .folderLayout(check):
      switch name {
      case .matchedFolders: .array(check.matchedFolders
          .map(RuntimeValue.string))
      case .missingFolders: .array(check.missingFolders
          .map(RuntimeValue.string))
      case .unexpectedFolders: .array(check.unexpectedFolders
          .map(RuntimeValue.string))
      default: nil
      }
    case let .packageDependencies(check):
      switch name {
      case .undeclared: checkArray(
          check.undeclared,
          RuntimeCheckValue.undeclaredDependency
        )
      case .unused: checkArray(check.unused, RuntimeCheckValue.unusedDependency)
      case .emptyTargets: .array(check.emptyTargets.map(RuntimeValue.string))
      case .checkedImportCount: .integer(check.checkedImportCount)
      case .isComplete: .boolean(check.isComplete)
      case .unresolvedManifestValues: modelArray(check
          .unresolvedManifestValues) { .manifest(.unresolvedValue($0)) }
      case .violations: importViolations(check.violations)
      default: nil
      }
    case let .dependencyStability(check):
      switch name {
      case .unstable: checkArray(
          check.unstable,
          RuntimeCheckValue.unstableDependency
        )
      case .emptyTargets: .array(check.emptyTargets.map(RuntimeValue.string))
      case .checkedEdgeCount: .integer(check.checkedEdgeCount)
      case .isComplete: .boolean(check.isComplete)
      case .unresolvedManifestValues: modelArray(check
          .unresolvedManifestValues) { .manifest(.unresolvedValue($0)) }
      case .violations: importViolations(check.violations)
      default: nil
      }
    case let .layering(check):
      switch name {
      case .emptyLayers: .array(check.emptyLayers.map(RuntimeValue.string))
      case .missingImports: checkArray(
          check.missingImports,
          RuntimeCheckValue.missingImport
        )
      case .violations: importViolations(check.violations)
      default: nil
      }
    case let .undeclaredDependency(value):
      switch name {
      case .target: .string(value.target)
      case .module: .string(value.module)
      case .importDeclaration: .model(.importDeclaration(value
            .importDeclaration))
      default: nil
      }
    case let .unusedDependency(value):
      switch name {
      case .target: .string(value.target)
      case .module: .string(value.module)
      default: nil
      }
    case let .unstableDependency(value):
      switch name {
      case .target: .string(value.target)
      case .importedTarget: .string(value.importedTarget)
      case .importDeclaration: .model(.importDeclaration(value
            .importDeclaration))
      case .instability: .double(value.instability)
      case .importedInstability: .double(value.importedInstability)
      default: nil
      }
    case let .missingImport(value):
      switch name {
      case .layer: .string(value.layer)
      case .requiredImport: .string(value.requiredImport)
      default: nil
      }
    case let .warning(value):
      switch name {
      case .message: .string(value.message)
      case .location: .model(.check(.location(value.location)))
      default: nil
      }
    case let .location(value):
      switch name {
      case .filePath: .string(value.filePath)
      case .fileName: .string(value.fileName)
      case .line: .integer(value.line)
      case .column: .integer(value.column)
      case .utf8Offset: .optional(value.utf8Offset.map(RuntimeValue.integer))
      default: nil
      }
    }
  }

  private func checkArray<T>(
    _ values: [T],
    _ wrap: (T) -> RuntimeCheckValue
  ) -> RuntimeValue {
    .array(values.map { .model(.check(wrap($0))) })
  }

  private func importViolations(_ value: Violations<Import>) -> RuntimeValue {
    .violations(RuntimeViolations(
      rule: value.rule,
      offenders: value.offenders.map(RuntimeModelValue.importDeclaration),
      checkedCount: value.checkedCount
    ))
  }
}
