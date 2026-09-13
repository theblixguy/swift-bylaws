import BylawsCore
import BylawsSemantics

enum RuntimeCheckValue: Sendable, Equatable {
  case packageDependencies(PackageDependencyCheck)
  case undeclaredDependency(PackageDependencyCheck.UndeclaredDependency)
  case unusedDependency(PackageDependencyCheck.UnusedDependency)
  case dependencyStability(DependencyStabilityCheck)
  case unstableDependency(DependencyStabilityCheck.UnstableDependency)
  case layering(LayeringCheck)
  case folderLayout(FolderLayoutCheck)
  case missingImport(LayeringCheck.MissingImport)
  case warning(Rule.Warning)
  case location(DeclarationLocation)

  var modelType: SupportedAPI.ModelType {
    switch self {
    case .packageDependencies: .packageDependencyCheck
    case .undeclaredDependency: .undeclaredDependency
    case .unusedDependency: .unusedDependency
    case .dependencyStability: .dependencyStabilityCheck
    case .unstableDependency: .unstableDependency
    case .layering: .layeringCheck
    case .folderLayout: .folderLayoutCheck
    case .missingImport: .missingImport
    case .warning: .ruleWarning
    case .location: .declarationLocation
    }
  }

  var ruleResult: (any RuleResult)? {
    switch self {
    case let .packageDependencies(value): value
    case let .dependencyStability(value): value
    case let .layering(value): value
    case let .folderLayout(value): value
    default: nil
    }
  }
}
