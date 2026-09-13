import BylawsSemantics

extension RuntimeTypeResolver {
  mutating func resolveConstructor(
    _ constructor: SupportedAPI.Constructor,
    typeArguments: [RuntimeType],
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    switch constructor {
    case .dictionary:
      return resolveDictionary(
        typeArguments: typeArguments,
        values: values,
        at: location
      )
    case .url:
      if !typeArguments.isEmpty {
        diagnose("URL takes no generic arguments", at: location)
      }
      guard values.map(\.0).equal([.fileURLWithPath]) else {
        diagnose(
          "URL takes arguments (fileURLWithPath:)",
          at: location,
          resolvingArguments: values
        )
        return .url
      }
      require(
        resolve(values[0].1),
        toMatch: .string,
        subject: "the file path",
        at: values[0].1.location
      )
      return .url
    case .dependencyGroup:
      if !typeArguments.isEmpty {
        diagnose("DependencyGroup takes no generic arguments", at: location)
      }
      guard values.map(\.0).equal([nil, .files]) else {
        diagnose(
          "DependencyGroup takes arguments (_, files:)",
          at: location, resolvingArguments: values
        )
        return .dependencyGroup
      }
      for (index, type) in [RuntimeType.string, .array(.string)].enumerated() {
        require(
          resolve(values[index].1, expected: type), toMatch: type,
          subject: "argument \(index + 1)", at: values[index].1.location
        )
      }
      return .dependencyGroup
    case .layer:
      return resolveLayer(values, at: location)
    case .layering:
      if resolveBuilder(values, builder: .layers, at: location) {
        return .layering
      }
      for (label, value) in values {
        let type = resolve(value)
        let matchesArray = values.count == 1 && type
          .isAssignable(to: .array(.layer))
        if label != nil || (type != .layer && !matchesArray) {
          diagnose("Layering takes Layer values", at: value.location)
        }
      }
      return .layering
    case .ruleResults:
      for (label, expression) in values {
        let type = resolve(expression)
        if label != nil || !type.isRuleResult {
          diagnose(
            "RuleResults takes unlabelled check results",
            at: expression.location
          )
        }
      }
      return .ruleResults
    case .matcher:
      guard typeArguments.count == 1,
            case let .model(subject) = typeArguments[0]
      else {
        diagnose(
          "Matcher takes one supported subject type",
          at: location,
          resolvingArguments: values
        )
        return .matcher(nil)
      }
      if values.count == 1, values[0].0 == nil,
         case let .keyPath(members) = resolve(values[0].1)
      {
        _ = resolveKeyPath(
          members,
          input: .model(subject),
          expectedResult: .boolean,
          at: location
        )
        return .matcher(subject)
      }
      guard values.map(\.0) == [nil, nil], values.count == 2 else {
        diagnose(
          "'Matcher' takes arguments (_, _)",
          at: location,
          resolvingArguments: values
        )
        return .matcher(subject)
      }
      require(
        resolve(values[0].1),
        toMatch: .string,
        subject: "argument 1",
        at: values[0].1.location
      )
      guard case let .closure(closure) = values[1].1.kind else {
        diagnose(
          "Matcher takes a closure predicate",
          at: values[1].1.location
        )
        return .matcher(subject)
      }
      _ = resolve(
        closure,
        parameters: [.model(subject)],
        expectedResult: .boolean,
        requiresSynchronousBody: true
      )
      return .matcher(subject)
    case .rule:
      guard let final = values.last,
            final.0 == nil,
            case let .closure(body) = final.1.kind
      else {
        diagnose(
          "Rule takes one trailing body closure",
          at: location,
          resolvingArguments: values
        )
        return .rule
      }
      let metadata = values.dropLast()
      let positional = metadata.filter { $0.0 == nil }
      if positional.count != 1, positional.count != 2 {
        diagnose("Rule takes an ID and an optional display name", at: location)
      }
      for argument in positional {
        require(
          resolve(argument.1),
          toMatch: .string,
          subject: "a Rule name",
          at: argument.1.location
        )
      }
      for argument in metadata where argument.0 != nil {
        switch argument.0.flatMap(
          SupportedAPI.ArgumentLabel.init(rawValue:)
        ) {
        case .enforcement:
          require(
            resolve(argument.1),
            toMatch: .staticMember([.enforcement]),
            subject: "'enforcement'",
            at: argument.1.location
          )
        case .hint:
          require(
            resolve(argument.1),
            toMatch: .string,
            subject: "'hint'",
            at: argument.1.location
          )
        default:
          diagnose(
            "portable rules do not support this Rule argument",
            at: argument.1.location
          )
        }
      }
      let result = resolve(
        body,
        parameters: [],
        expectedResult: nil,
        requiresSynchronousBody: false,
        builder: .checks
      ).result
      if !result.isRuleResult {
        diagnose(
          "Rule must return a check result, Violations or Rule.Findings",
          at: body.location
        )
      }
      return .rule
    case .violations:
      guard values.map(\.0).equal([.rule, .offenders, .checkedCount]) else {
        diagnose(
          "'Violations' takes arguments (rule:, offenders:, checkedCount:)",
          at: location,
          resolvingArguments: values
        )
        return .violations(typeArguments.first?.modelType)
      }
      require(
        resolve(values[0].1),
        toMatch: .string,
        subject: "'rule'",
        at: values[0].1.location
      )
      let offenders = resolve(values[1].1)
      guard case let .array(offender) = offenders else {
        diagnose("'offenders' must be an array", at: values[1].1.location)
        return .violations(typeArguments.first?.modelType)
      }
      if let expected = typeArguments.first {
        require(
          offender,
          toMatch: expected,
          subject: "the offenders",
          at: values[1].1.location
        )
      }
      require(
        resolve(values[2].1),
        toMatch: .integer,
        subject: "'checkedCount'",
        at: values[2].1.location
      )
      return .violations(typeArguments.first?.modelType ?? offender.modelType)
    case .array:
      if typeArguments.isEmpty || typeArguments == [.rule], resolveBuilder(
        values,
        builder: .rules,
        at: location
      ) { return .array(.rule) }
      guard values.isEmpty else {
        diagnose(
          "portable rules do not support this 'Array' initialiser",
          at: location,
          resolvingArguments: values
        )
        return .array(typeArguments.first ?? .unknown)
      }
      return .array(typeArguments.first ?? .unknown)
    case .set:
      if let element = typeArguments.first, !element.supportsHashing {
        diagnose("Set cannot contain \(element.writtenName)", at: location)
      }
      if values.isEmpty { return .set(typeArguments.first ?? .unknown) }
      guard values.map(\.0) == [nil], values.count == 1 else {
        diagnose("'Set' takes arguments (_)", at: location)
        return .set(typeArguments.first ?? .unknown)
      }
      let value = resolve(values[0].1)
      guard case let .array(element) = value else {
        diagnose("argument 1 must be an array", at: values[0].1.location)
        return .set(typeArguments.first ?? .unknown)
      }
      if !element.supportsHashing {
        diagnose("Set cannot contain \(element.writtenName)", at: location)
      }
      if let expected = typeArguments.first {
        require(
          element,
          toMatch: expected,
          subject: "the array element",
          at: values[0].1.location
        )
      }
      return .set(element)
    case .trivia:
      guard values.map(\.0).equal([.pieces]) else {
        diagnose(
          "'Trivia' takes arguments (pieces:)",
          at: location,
          resolvingArguments: values
        )
        return .string
      }
      require(
        resolve(values[0].1),
        toMatch: .array(.model(.syntaxTriviaPiece)),
        subject: "'pieces'",
        at: values[0].1.location
      )
      return .string
    }
  }

  private mutating func diagnose(
    _ message: String,
    at location: DeclarationLocation,
    resolvingArguments values: [(String?, RuntimeExpression)]
  ) {
    diagnose(message, at: location)
    values.forEach { _ = resolve($0.1) }
  }

  mutating func resolvePrebuiltMatcher(
    _ name: String,
    values: [(String?, RuntimeExpression)],
    at location: DeclarationLocation
  ) -> RuntimeType {
    guard let matcher = SupportedAPI.matcher(named: name) else {
      diagnose("'\(name)' is not a supported static member", at: location)
      return .matcher(nil)
    }
    if !matcher.arguments.accepts(labels: values.map(\.0)) {
      diagnose("'\(name)' \(matcher.arguments.requirement)", at: location)
    }
    values.forEach { _ = resolve($0.1) }
    let subjects = matcher.declarationFamilies.compactMap(
      SupportedAPI.ModelType.init(declarationFamily:)
    )
    return .matcher(subjects.count == 1 ? subjects[0] : nil)
  }
}
