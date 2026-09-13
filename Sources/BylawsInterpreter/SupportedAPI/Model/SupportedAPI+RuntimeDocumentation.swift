extension SupportedAPI {
  package static var runtimeCapabilityMarkdown: String {
    let receivers = Set(runtimeMembers.flatMap(\.receivers))
      .filter { if case .staticType = $0 { false } else { true } }
      .sorted { $0.documentationName < $1.documentationName }
    let rows = receivers.map { receiver in
      let entries = runtimeMembers.filter { $0.receivers.contains(receiver) }
      let properties: [String] = entries.compactMap { entry in
        guard case .property = entry.kind else { return nil }
        return entry.name.rawValue
      }
      let methods: [String] = entries.compactMap { entry in
        guard case let .method(call) = entry.kind else { return nil }
        return call.method.rawValue
      }
      return "| `\(receiver.documentationName)` | \(render(properties)) | \(render(methods)) |"
    }
    return ([
      "| Receiver | Properties | Methods |",
      "| --- | --- | --- |",
    ] + rows).joined(separator: "\n")
  }

  private static func render(_ names: [String]) -> String {
    let names = Set(names).sorted()
    return names.isEmpty ? "None" : names.map { "`\($0)`" }
      .joined(separator: ", ")
  }
}

extension SupportedAPI.RuntimeReceiver {
  fileprivate var documentationName: String {
    switch self {
    case .url: "URL"
    case .dictionary: "Dictionary"
    case .array: "Array"
    case .manifestList: "ManifestList"
    case .set: "Set"
    case .string: "String"
    case .codebase: "Codebase"
    case .dependencyGroup: "DependencyGroup"
    case .selection: "Selection"
    case let .model(model): model.rawValue
    case .matcher: "Matcher"
    case .projectIndex: "ProjectIndex"
    case .symbolRoles: "Set<SymbolRole>"
    case .violations: "Violations"
    case .findings: "Rule.Findings"
    case .ruleResults: "RuleResults"
    case .integerRange: "Range<Int>"
    case let .staticType(name): "\(name).Type"
    }
  }
}
