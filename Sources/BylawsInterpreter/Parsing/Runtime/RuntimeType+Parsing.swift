import BylawsSemantics

extension SupportedAPI.RuntimeType {
  init(writtenType: String) {
    let reference = TypeReference(writtenType)
    let nominalName = Self.nominalName(in: reference)
    let base: Self = if nominalName == "Rule.Findings" {
      .findings
    } else if let type = SupportedAPI.StaticMemberType(
      rawValue: nominalName
    ) {
      .staticMember([type.owner])
    } else {
      switch reference.name {
      case "Void", "()": .void
      case "Bool": .boolean
      case "Int": .integer
      case "Double": .double
      case "String": .string
      case "URL": .url
      case "Dictionary":
        if reference.genericArguments.count == 2 {
          .dictionary(
            key: Self(writtenType: reference.genericArguments[0].text),
            value: Self(writtenType: reference.genericArguments[1].text)
          )
        } else {
          .unknown
        }
      case "Array":
        if let argument = Self.singleGenericArgument(of: reference) {
          .array(Self(writtenType: argument.text))
        } else {
          .unknown
        }
      case "ManifestList":
        if let argument = Self.singleGenericArgument(of: reference) {
          .manifestList(Self(writtenType: argument.text))
        } else {
          .unknown
        }
      case "Set":
        if let argument = Self.singleGenericArgument(of: reference) {
          Self.nominalName(in: argument) == "SymbolRole"
            ? .symbolRoles : .set(Self(writtenType: argument.text))
        } else {
          .unknown
        }
      case "Range":
        if let argument = Self.singleGenericArgument(of: reference),
           argument.name == "Int"
        {
          .integerRange
        } else {
          .unknown
        }
      case "Codebase": .codebase
      case "DependencyGroup": .dependencyGroup
      case "Layering": .layering
      case "Layer": .layer
      case "RuleResults": .ruleResults
      case "ProjectIndex": .projectIndex
      case "Matcher":
        if let argument = Self.singleGenericArgument(of: reference) {
          SupportedAPI.ModelType(rawValue: Self.nominalName(in: argument))
            .map(Self.matcher) ?? .unknown
        } else {
          .unknown
        }
      case "Violations":
        if let argument = Self.singleGenericArgument(of: reference) {
          SupportedAPI.ModelType(rawValue: Self.nominalName(in: argument))
            .map(Self.violations) ?? .unknown
        } else {
          .unknown
        }
      case "Rule": .rule
      default:
        SupportedAPI.ModelType(rawValue: nominalName).map(Self.model)
          ?? .unknown
      }
    }
    self = reference.isOptional ? .optional(base) : base
  }

  private static func singleGenericArgument(
    of reference: TypeReference
  ) -> TypeReference? {
    reference.genericArguments.count == 1 ? reference.genericArguments[0] : nil
  }

  private static func nominalName(in reference: TypeReference) -> String {
    var name = String(reference.text.filter { !$0.isWhitespace })
    guard reference.isOptional else { return name }
    if name.last == "?" || name.last == "!" {
      name.removeLast()
      return name
    }
    let prefix = "Optional<"
    guard name.hasPrefix(prefix), name.last == ">" else { return name }
    return String(name.dropFirst(prefix.count).dropLast())
  }

  var containsUnknown: Bool {
    switch self {
    case let .dictionary(key, value):
      key.containsUnknown || value.containsUnknown
    case .unknown:
      true
    case let .array(element), let .manifestList(element), let .set(element),
         let .optional(element):
      element.containsUnknown
    case let .constructor(_, arguments):
      arguments.contains(where: \.containsUnknown)
    case let .function(function):
      function.parameters.contains { $0.type.containsUnknown }
        || function.result.containsUnknown
    case let .closure(closure):
      closure.parameters.contains(where: \.containsUnknown)
        || closure.result.containsUnknown
    default:
      false
    }
  }

  var receiver: SupportedAPI.RuntimeReceiver? {
    switch self {
    case .url: .url
    case .dictionary: .dictionary
    case .array: .array
    case .manifestList: .manifestList
    case .set: .set
    case .string: .string
    case .codebase: .codebase
    case .dependencyGroup: .dependencyGroup
    case .selection: .selection
    case let .model(model): .model(model)
    case .matcher: .matcher
    case .projectIndex: .projectIndex
    case .symbolRoles: .symbolRoles
    case .violations: .violations
    case .findings: .findings
    case .ruleResults: .ruleResults
    case .integerRange: .integerRange
    case let .staticType(name): .staticType(name)
    case .constructor(.matcher, _): .staticType("Matcher")
    default: nil
    }
  }

  var receiverName: String {
    switch self {
    case .dictionary: "Dictionary"
    case .array: "Array"
    case .manifestList: "ManifestList"
    case .set: "Set"
    case let .selection(family):
      SupportedAPI.ModelType(declarationFamily: family)?.rawValue ?? "Selection"
    case let .model(model): model.rawValue
    default: writtenName
    }
  }

  var collectionElement: Self {
    switch self {
    case let .array(element): element
    case let .manifestList(element): element
    case let .set(element): element
    case let .selection(family):
      SupportedAPI.ModelType(declarationFamily: family)
        .map(Self.model) ?? .unknown
    default: .unknown
    }
  }

  var sequenceElement: Self? {
    switch self {
    case let .array(element), let .set(element): element
    case .selection: collectionElement
    default: nil
    }
  }

  var modelType: SupportedAPI.ModelType? {
    if case let .model(type) = self { return type }
    return nil
  }

  var isRuleResult: Bool {
    switch self {
    case .violations, .findings, .ruleResults,
         .model(.packageDependencyCheck), .model(.dependencyStabilityCheck),
         .model(.layeringCheck), .model(.folderLayoutCheck): true
    default: false
    }
  }

  var isComparable: Bool {
    self == .integer || self == .double || self == .string
  }

  var supportsAddition: Bool {
    switch self {
    case .integer, .double, .string, .array: true
    default: false
    }
  }

  func isAssignable(to expected: Self) -> Bool {
    if self == .unknown || expected == .unknown || self == expected {
      return true
    }
    return switch (self, expected) {
    case let (
      .dictionary(actualKey, actualValue),
      .dictionary(wantedKey, wantedValue)
    ):
      actualKey.isAssignable(to: wantedKey) && actualValue
        .isAssignable(to: wantedValue)
    case let (.array(actual), .array(wanted)):
      actual.isAssignable(to: wanted)
    case let (.manifestList(actual), .manifestList(wanted)):
      actual.isAssignable(to: wanted)
    case let (.set(actual), .set(wanted)):
      actual.isAssignable(to: wanted)
    case let (.optional(actual), .optional(wanted)):
      actual.isAssignable(to: wanted)
    case let (.staticMember(actual), .staticMember(wanted)):
      !actual.isDisjoint(with: wanted)
    case (.matcher(nil), .matcher), (.violations(nil), .violations): true
    case let (actual, .optional(wanted)):
      actual.isAssignable(to: wanted)
    default: false
    }
  }

  var optionalChained: Self {
    if case .optional = self { return self }
    return .optional(self)
  }
}
