extension SupportedAPI {
  package indirect enum RuntimeType: Equatable, Sendable {
    case unknown
    case void
    case boolean
    case integer
    case double
    case string
    case url
    case dictionary(key: RuntimeType, value: RuntimeType)
    case array(RuntimeType)
    case manifestList(RuntimeType)
    case set(RuntimeType)
    case optional(RuntimeType)
    case codebase
    case dependencyGroup
    case layering
    case layer
    case selection(DeclarationFamily)
    case model(ModelType)
    case matcher(ModelType?)
    case projectIndex
    case symbolRoles
    case violations(ModelType?)
    case findings
    case ruleResults
    case rule
    case integerRange
    case staticType(String)
    case staticMember(Set<MemberLiteral.Owner>)
    case keyPath([Member])
    case constructor(Constructor, [RuntimeType])
    case boundMethod(
      receiver: RuntimeType,
      call: RuntimeCall,
      canSuspend: Bool
    )
    case prebuiltMatcher(String)
    case function(RuntimeFunctionType)
    case closure(RuntimeClosureType)

    package var writtenName: String {
      switch self {
      case .unknown: "an inferred value"
      case .void: "Void"
      case .boolean: "Bool"
      case .integer: "Int"
      case .double: "Double"
      case .string: "String"
      case .url: "URL"
      case let .dictionary(key, value):
        "[\(key.writtenName): \(value.writtenName)]"
      case let .array(element): "[\(element.writtenName)]"
      case let .manifestList(element): "ManifestList<\(element.writtenName)>"
      case let .set(element): "Set<\(element.writtenName)>"
      case let .optional(wrapped): "\(wrapped.writtenName)?"
      case .codebase: "Codebase"
      case .dependencyGroup: "DependencyGroup"
      case .layering: "Layering"
      case .layer: "Layer"
      case let .selection(family):
        "Selection<\(ModelType(declarationFamily: family)?.rawValue ?? family.rawValue)>"
      case let .model(model): model.rawValue
      case let .matcher(subject):
        subject.map { "Matcher<\($0.rawValue)>" } ?? "Matcher"
      case .projectIndex: "ProjectIndex"
      case .symbolRoles: "Set<SymbolRole>"
      case let .violations(subject):
        subject.map { "Violations<\($0.rawValue)>" } ?? "Violations"
      case .findings: "Rule.Findings"
      case .ruleResults: "RuleResults"
      case .rule: "Rule"
      case .integerRange: "Range<Int>"
      case let .staticType(name): "\(name).Type"
      case .staticMember: "a static member"
      case .keyPath: "a key path"
      case let .constructor(constructor, _): "\(constructor.rawValue).Type"
      case .boundMethod: "a method"
      case .prebuiltMatcher: "a Matcher"
      case .function: "a function"
      case .closure: "a closure"
      }
    }
  }

  package struct RuntimeParameter: Equatable, Sendable {
    package let label: String?
    package let type: RuntimeType
  }

  package struct RuntimeFunctionType: Equatable, Sendable {
    package let name: String
    package let parameters: [RuntimeParameter]
    package let result: RuntimeType
    package let isAsync: Bool
    package let isThrowing: Bool
  }

  package struct RuntimeClosureType: Equatable, Sendable {
    package let parameters: [RuntimeType]
    package let result: RuntimeType
    package let isAsync: Bool
    package let isThrowing: Bool
  }

  package enum RuntimeReceiver: Hashable, Sendable {
    case url
    case dictionary
    case dependencyGroup
    case ruleResults
    case array
    case manifestList
    case set
    case string
    case codebase
    case selection
    case model(ModelType)
    case matcher
    case projectIndex
    case symbolRoles
    case violations
    case findings
    case integerRange
    case staticType(String)
  }

  package enum RuntimeResult: Equatable, Sendable {
    case mappedDictionary
    case fixed(RuntimeType)
    case receiver
    case collection
    case optionalCollectionElement
    case manifestListKnownValues
    case manifestListConditionalValues
    case manifestListPossibleValues
    case manifestListValues
    case closureResult
    case optionalClosureResult
    case flattenedClosureResult
    case syntaxClosureResult
    case violationsForSelection
    case violationOffenders
  }

  package enum RuntimeArgumentType: Equatable, Sendable {
    case dictionaryValueCallable
    case any
    case stringOrStringArray
    case exact(RuntimeType)
    case sequenceOfCollectionElement
    case collectionCallable(result: RuntimeType?)
    case collectionElement
    case callable(input: RuntimeType, result: RuntimeType?)
    case matcherForSelection
    case selectionFilter
  }

  package struct RuntimeCallParameter: Equatable, Sendable {
    package let label: ArgumentLabel?
    package let type: RuntimeArgumentType

    package init(
      _ label: ArgumentLabel? = nil,
      _ type: RuntimeArgumentType = .any
    ) {
      self.label = label
      self.type = type
    }
  }

  package enum RuntimeCallArguments: Equatable, Sendable {
    case exact([RuntimeCallParameter])
    case alternatives([[RuntimeCallParameter]])
    case unlabelledStrings
    case optional(RuntimeCallParameter)
    case variadic(
      first: RuntimeCallParameter,
      additional: RuntimeCallParameter
    )
    case indexQuery(
      leading: [RuntimeCallParameter],
      optional: [RuntimeCallParameter]
    )
  }

  package struct RuntimeCall: Equatable, Sendable {
    package let method: Method
    package let arguments: RuntimeCallArguments
    package let result: RuntimeResult
  }

  package enum RuntimeMemberKind: Equatable, Sendable {
    case property(RuntimeResult)
    case method(RuntimeCall)
  }

  package struct RuntimeMemberAPI: Equatable, Sendable {
    package let receivers: Set<RuntimeReceiver>
    package let name: Member
    package let kind: RuntimeMemberKind
    package let canSuspend: Bool
  }

  package static let staticMemberTypeNames: Set<String> =
    Set(StaticMemberType.allCases.map(\.rawValue))

  package static let runtimeTypeNames: Set<String> = Set(ModelType.allCases
    .map(\.rawValue))
    .union(Constructor.allCases.map(\.rawValue))
    .union(staticMemberTypeNames)
}
