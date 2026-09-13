extension SupportedAPI.RuntimeCallArguments {
  func accepts(labels: [String?]) -> Bool {
    switch self {
    case let .exact(parameters):
      return labels == parameters.map(\.writtenLabel)
    case let .alternatives(alternatives):
      return alternatives.contains { labels == $0.map(\.writtenLabel) }
    case .unlabelledStrings:
      return !labels.isEmpty && labels.allSatisfy { $0 == nil }
    case let .optional(parameter):
      return labels.isEmpty || labels == [parameter.writtenLabel]
    case let .indexQuery(leading, optional):
      guard labels.count >= leading.count,
            Array(labels.prefix(leading.count)) == leading.map(\.writtenLabel)
      else { return false }
      let tail = labels.dropFirst(leading.count)
      let allowed = Set(optional.map(\.writtenLabel))
      return tail.allSatisfy { allowed.contains($0) }
        && Set(tail).count == tail.count
    }
  }

  func parameters(
    for labels: [String?],
    expressions: [RuntimeExpression]
  ) -> [SupportedAPI.RuntimeCallParameter] {
    switch self {
    case let .exact(parameters): return parameters
    case let .alternatives(alternatives):
      let matching = alternatives.filter {
        labels == $0.map(\.writtenLabel)
      }
      if let callable = matching.first(where: { parameters in
        zip(parameters, expressions).contains { parameter, expression in
          guard parameter.type.isCallable else { return false }
          switch expression.kind {
          case .closure, .keyPath: return true
          default: return false
          }
        }
      }) {
        return callable
      }
      return matching.first { parameters in
        !parameters.contains { $0.type.isCallable }
      } ?? matching.first ?? []
    case .unlabelledStrings:
      return labels.map { _ in
        SupportedAPI.RuntimeCallParameter(nil, .exact(.string))
      }
    case let .optional(parameter):
      return labels.isEmpty ? [] : [parameter]
    case let .indexQuery(leading, optional):
      return leading + labels.dropFirst(leading.count).compactMap { label in
        optional.first { $0.writtenLabel == label }
      }
    }
  }

  var leadingLabels: [SupportedAPI.ArgumentLabel] {
    switch self {
    case let .exact(parameters): parameters.compactMap(\.label)
    case let .indexQuery(leading, _): leading.compactMap(\.label)
    case .alternatives, .unlabelledStrings, .optional: []
    }
  }

  var trailingLabels: [SupportedAPI.ArgumentLabel] {
    guard case let .indexQuery(_, optional) = self else { return [] }
    return optional.compactMap(\.label)
  }

  var rendered: String {
    switch self {
    case let .exact(parameters): labelList(of: parameters)
    case let .alternatives(alternatives):
      alternatives.map(labelList(of:))
        .reduce(into: [String]()) { result, value in
          if !result.contains(value) { result.append(value) }
        }.joined(separator: " or ")
    case .unlabelledStrings: "one or more unlabelled strings"
    case let .optional(parameter): "() or \(labelList(of: [parameter]))"
    case let .indexQuery(leading, optional):
      labelList(of: leading + optional)
    }
  }

  private func labelList(
    of parameters: [SupportedAPI.RuntimeCallParameter]
  ) -> String {
    argumentLabelList(parameters.map(\.writtenLabel))
  }
}
