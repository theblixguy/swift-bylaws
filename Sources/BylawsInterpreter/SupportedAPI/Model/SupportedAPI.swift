package enum SupportedAPI {
  package enum Declaration: String, Sendable {
    case rule = "Rule"
    case override = "Override"
  }

  package enum Value: String, Sendable {
    case codebase = "Codebase"
    case layering = "Layering"
    case layer = "Layer"
  }

  package enum CodebaseOperation: String, Sendable {
    case checkPackageDependencies
    case checkDependencyStability
    case importGraph

    package var arguments: ArgumentContract {
      switch self {
      case .checkPackageDependencies, .checkDependencyStability:
        .optionalStringArray(labelled: .ignoring)
      case .importGraph:
        .none
      }
    }
  }

  package enum CodebaseRoot: String, Sendable {
    case automatic
    case directory
  }

  package enum SelectionOperation: String, Sendable {
    case violations
  }

  package enum LayerImportPolicy: String, Sendable {
    case any
  }

  package enum ArgumentLabel: String, Sendable {
    case fileURLWithPath
    case grouping
    case by
    case `as`
    case reportedAt
    case checkedCount
    case including
    case excluding
    case root
    case files
    case ignoring
    case modules
    case mayImport
    case mustImport
    case mustNotImport
    case enforcement
    case hint
    case reason
    case of
    case matching
    case allowingReferencesTo
    case allowingWithinFoldersMatching
    case between
    case inFoldersMatching
    case outsidePaths
    case named
    case from
    case to
    case typed
    case labelled
    case referencing
    case atLeast
    case offenders
    case pieces
    case rule
    case unitOutputFiles
    case viewMode
    case `where`
    case containing
    case dependingDirectlyOn
    case dependingOn
    case includingConditionalDependencies
  }

  package enum DeclarationFamily: String, CaseIterable, Sendable {
    case file
    case `class`
    case actor
    case `struct`
    case `enum`
    case nominalType
    case `protocol`
    case `extension`
    case function
    case property
    case initializer
    case `import`
    case `typealias`
    case functionCall
  }

  package static let allDeclarationFamilies = Set(DeclarationFamily.allCases)

  package enum ArgumentContract: Equatable, Sendable {
    case none
    case strings(startingWith: ArgumentLabel?)
    case oneString(labelled: ArgumentLabel?)
    case optionalStringArray(labelled: ArgumentLabel)
    case functionParameter
    case visibility

    package var requirement: String {
      switch self {
      case .none:
        "takes no arguments"
      case let .strings(.some(label)):
        "takes strings after '\(label.rawValue):' or one string array"
      case .strings(.none):
        "takes string literals or one string array"
      case let .oneString(.some(label)):
        "takes one string literal after '\(label.rawValue):'"
      case .oneString(.none):
        "takes one string literal"
      case let .optionalStringArray(label):
        "takes one string array after '\(label.rawValue):'"
      case .functionParameter:
        "takes 'typed:', 'labelled:' or strings after 'referencing:'"
      case .visibility:
        "takes a visibility after 'atLeast:'"
      }
    }
  }
}
