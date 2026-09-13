import BylawsCore
import BylawsPaths
import BylawsSemantics

extension RuntimeEvaluator {
  func selectionMethod(
    _ name: SupportedAPI.Method,
    selection: RuntimeSelection,
    arguments: RuntimeArguments,
    state: inout RuntimeEvaluationState
  ) async throws(RuntimeError) -> RuntimeValue {
    if let filter = SupportedAPI.Filter.ID(rawValue: name.rawValue) {
      return try filterSelection(
        filter,
        selection: selection,
        arguments: arguments
      )
    }
    switch name {
    case .where:
      try arguments.requireLabels([nil], for: name)
      let argument = try arguments.value(at: 0)
      if case let .keyPath(path, _) = argument {
        var elements: [RuntimeModelValue] = []
        for value in selection.elements
          where try await predicate(
            argument,
            value: .model(value),
            state: &state
          )
        {
          elements.append(value)
        }
        return .selection(
          selection.narrowed(
            to: elements,
            queryDescription:
            "\(selection.queryDescription) where \(path.map(\.rawValue).joined(separator: ".")) is true"
          )
        )
      }
      let condition = try matcherValue(
        from: argument,
        location: arguments.location
      )
      var elements: [RuntimeModelValue] = []
      for value in selection.elements
        where try await matches(
          condition,
          value: value,
          state: &state
        )
      {
        elements.append(value)
      }
      return .selection(
        selection.narrowed(
          to: elements,
          queryDescription:
          "\(selection.queryDescription) that \(requirement(of: condition, for: selection.family))"
        )
      )
    case .violations:
      if arguments.label(at: 0) == .outsidePaths {
        return try pathViolations(in: selection, arguments: arguments)
      }
      guard arguments.values.count == 1,
            let label = arguments.label(at: 0),
            label == .of || label == .matching
      else {
        throw RuntimeError(
          message: "'violations' takes 'of:', 'matching:' or 'outsidePaths:'",
          location: arguments.location
        )
      }
      let matcher = try matcherValue(
        from: arguments.value(at: 0),
        location: arguments.location
      )
      let expectsMatch = label == .matching
      var offenders: [RuntimeModelValue] = []
      var witnesses: [DeclarationLocation?] = []
      for value in selection.elements {
        let result = try await match(matcher, value: value, state: &state)
        if expectsMatch == result.matches, value.offender != nil {
          offenders.append(value)
          witnesses.append(result.witness)
        }
      }
      let description = requirement(of: matcher, for: selection.family)
      return .violations(
        RuntimeViolations(
          rule: expectsMatch ? "not \(description)" : description,
          offenders: offenders,
          checkedCount: selection.elements.count,
          witnesses: witnesses
        )
      )
    case .filter, .map, .compactMap, .flatMap, .contains, .allSatisfy:
      return try await collectionMethod(
        name,
        values: selection.elements.map(RuntimeValue.model),
        preservesSet: false,
        arguments: arguments,
        state: &state
      )
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported Selection method",
        location: arguments.location
      )
    }
  }

  private func filterSelection(
    _ filter: SupportedAPI.Filter.ID,
    selection: RuntimeSelection,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    let strings: [String]
    if filter == .nameMatching {
      try arguments.requireLabels([nil], for: filter.rawValue)
      strings = [try arguments.string(at: 0)]
    } else if arguments.values.count == 1,
              case .array = arguments.values[0].value
    {
      try arguments.requireLabels([nil], for: filter.rawValue)
      strings = try arguments.strings(at: 0)
    } else {
      guard arguments.values.allSatisfy({ $0.label == nil }) else {
        throw RuntimeError(
          message: "'\(filter.rawValue)' takes unlabelled strings",
          location: arguments.location
        )
      }
      strings = try arguments.values.indices.map(arguments.string(at:))
    }
    let values = filter == .under || filter == .outside
      ? strings.map { LexicalFilePath($0).string }
      : strings
    let directories = selection.rootPath.map {
      rootPath -> [LexicalFilePath] in
      let root = LexicalFilePath(rootPath)
      return values.compactMap(root.resolvingDescendant)
    } ?? [LexicalFilePath]()
    let patterns: [NamePattern]
    if filter == .nameMatching {
      do {
        patterns = try values.map(NamePattern.init)
      } catch {
        throw RuntimeError(wrapping: error, at: arguments.location)
      }
    } else {
      patterns = []
    }
    let elements = selection.elements.filter { value in
      switch filter {
      case .named: value.name.map(values.contains) == true
      case .suffixed:
        value.name.map { candidate in
          values.contains { candidate.hasSuffix($0) }
        } == true
      case .prefixed:
        value.name.map { candidate in
          values.contains { candidate.hasPrefix($0) }
        } == true
      case .excluding: value.name.map { !values.contains($0) } == true
      case .nameMatching:
        value.name.map { candidate in
          patterns.contains { $0.matches(candidate) }
        } == true
      case .under:
        value.filePath.map { path in
          let path = LexicalFilePath(path)
          return directories.contains { $0.contains(path) }
        } == true
      case .outside:
        value.filePath.map { path in
          let path = LexicalFilePath(path)
          return !directories.contains { $0.contains(path) }
        } == true
      }
    }
    let quoted = values.map { "'\($0)'" }.joined(separator: " or ")
    let detail =
      switch filter {
      case .named: "named \(quoted)"
      case .suffixed: "suffixed \(quoted)"
      case .prefixed: "prefixed \(quoted)"
      case .excluding: "excluding \(quoted)"
      case .nameMatching: "with a name matching /\(values[0])/"
      case .under: "under \(quoted)"
      case .outside: "outside \(quoted)"
      }
    return .selection(
      selection.narrowed(
        to: elements,
        queryDescription: "\(selection.queryDescription) \(detail)"
      )
    )
  }
}
