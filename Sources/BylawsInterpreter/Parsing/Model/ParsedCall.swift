import BylawsSemantics

struct ParsedCall: Sendable {
  struct Argument: Sendable {
    let rawLabel: String?
    let value: LiteralValue

    var label: SupportedAPI.ArgumentLabel? {
      rawLabel.flatMap(SupportedAPI.ArgumentLabel.init)
    }

    // An unsupported label matches no label, so compare the written text.
    func hasLabel(_ label: SupportedAPI.ArgumentLabel?) -> Bool {
      rawLabel == label.written
    }

    var matcher: MatcherExpression? {
      guard case let .matcher(expression) = value else { return nil }
      return expression
    }
  }

  let name: String
  let arguments: [Argument]
  let location: DeclarationLocation

  var unlabelledStrings: [String] {
    arguments.filter { $0.rawLabel == nil }.flatMap(\.value.stringValues)
  }

  func strings(labelled label: SupportedAPI.ArgumentLabel) -> [String] {
    arguments.filter { $0.hasLabel(label) }
      .flatMap(\.value.stringValues)
  }

  func strings(startingWith label: SupportedAPI.ArgumentLabel) -> [String] {
    guard let first = arguments.first else { return [] }
    return first.hasLabel(label)
      ? arguments.flatMap(\.value.stringValues)
      : []
  }

  func member(labelled label: SupportedAPI.ArgumentLabel) -> String? {
    guard arguments.count == 1,
          arguments[0].hasLabel(label),
          case let .member(name) = arguments[0].value
    else { return nil }
    return name
  }

  func accepts(_ contract: SupportedAPI.ArgumentContract) -> Bool {
    switch contract {
    case .none:
      arguments.isEmpty
    case let .strings(startingWith: label):
      acceptsStrings(startingWith: label)
    case let .oneString(labelled: label):
      arguments.count == 1
        && arguments[0].hasLabel(label)
        && arguments[0].value.isString
    case let .optionalStringArray(labelled: label):
      arguments.isEmpty
        || (arguments.count == 1
          && arguments[0].hasLabel(label)
          && arguments[0].value.isStringArray)
    case .functionParameter:
      arguments.isEmpty
        || accepts(.oneString(labelled: .typed))
        || accepts(.oneString(labelled: .labelled))
        || accepts(.strings(startingWith: .referencing))
    case .visibility:
      acceptsVisibility
    }
  }

  private func acceptsStrings(
    startingWith label: SupportedAPI.ArgumentLabel?
  ) -> Bool {
    if arguments.isEmpty { return true }
    if arguments.count == 1,
       arguments[0].hasLabel(label),
       case .strings = arguments[0].value
    {
      return true
    }
    return arguments.enumerated().allSatisfy { index, argument in
      argument.hasLabel(index == 0 ? label : nil)
        && argument.value.isString
    }
  }

  private var acceptsVisibility: Bool {
    let levels = Set(Visibility.allCases.map(\.rawValue))
    return member(labelled: .atLeast).map(levels.contains) == true
  }
}

indirect enum LiteralValue: Sendable {
  case string(String)
  case strings([String])
  case member(String)
  case reference(String)
  case matcher(MatcherExpression)

  var stringValues: [String] {
    switch self {
    case let .string(value): [value]
    case let .strings(values): values
    case .member, .reference, .matcher: []
    }
  }

  var isString: Bool {
    if case .string = self { true } else { false }
  }

  var isStringArray: Bool {
    if case .strings = self { true } else { false }
  }
}

indirect enum MatcherExpression: Sendable {
  case leaf(ParsedCall)
  case and(MatcherExpression, MatcherExpression)
  case or(MatcherExpression, MatcherExpression)
  case not(MatcherExpression)
}
