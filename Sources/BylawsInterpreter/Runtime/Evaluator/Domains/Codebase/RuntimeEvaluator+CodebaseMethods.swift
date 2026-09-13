import BylawsCore
import BylawsSemantics

extension RuntimeEvaluator {
  func codebaseMethod(
    _ name: SupportedAPI.Method,
    codebase: Codebase,
    arguments: RuntimeArguments
  ) async throws(RuntimeError) -> RuntimeValue {
    switch name {
    case .dependencyGroups:
      let groups = try await reportingFailures(at: arguments.location) {
        try await codebase.dependencyGroups(
          inFoldersMatching: arguments.string(at: 0)
        )
      }
      return .array(groups.map(RuntimeValue.dependencyGroup))
    case .checkDependencies, .checkDependencyCycles:
      return try await dependencyCheck(
        name,
        codebase: codebase,
        arguments: arguments
      )
    case .checkFolderLayout:
      try arguments.requireLabels([.matching, .containing], for: name)
      let pattern = try arguments.string(at: 0)
      let folders = try arguments.strings(at: 1)
      let check = try await reportingFailures(at: arguments.location) {
        try await codebase.checkFolderLayout(
          matching: pattern,
          containing: folders
        )
      }
      return .model(.check(.folderLayout(check)))
    case .indexedFindings:
      let index = try projectIndex(
        over: codebase,
        arguments,
        declaredBy: try indexQueryCall(
          name,
          on: .codebase,
          at: arguments.location
        )
      )
      guard case let .layering(layering) = try arguments.value(at: 0) else {
        throw RuntimeError(
          message: "'indexedFindings(of:)' takes a Layering",
          location: arguments.location
        )
      }
      let provider = try requireIndexProvider(at: arguments.location)
      let findings = try await reportingFailures(at: arguments.location) {
        try await provider.indexedFindings(
          of: layering,
          in: index,
          location: arguments.location
        )
      }
      return .findings(findings)
    case .checkLayering:
      try arguments.requireLabels([nil], for: name)
      guard case let .layering(layering) = try arguments.value(at: 0) else {
        throw RuntimeError(
          message: "checkLayering takes one Layering",
          location: arguments.location
        )
      }
      let check = try await reportingFailures(at: arguments.location) {
        try await codebase.checkLayering(layering)
      }
      return .model(.check(.layering(check)))
    case .checkPackageDependencies:
      let ignored = try ignoredTargets(arguments, method: name)
      let check = try await reportingFailures(at: arguments.location) {
        try await codebase.checkPackageDependencies(ignoring: ignored)
      }
      return .model(.check(.packageDependencies(check)))
    case .checkDependencyStability:
      let ignored = try ignoredTargets(arguments, method: name)
      let check = try await reportingFailures(at: arguments.location) {
        try await codebase.checkDependencyStability(ignoring: ignored)
      }
      return .model(.check(.dependencyStability(check)))
    case .importGraph:
      try arguments.requireLabels([], for: name)
      let graph = try await reportingFailures(at: arguments.location) {
        try await codebase.importGraph()
      }
      return .model(.importGraph(graph))
    case .projectIndex:
      let index = try projectIndex(
        over: codebase,
        arguments,
        declaredBy: try indexQueryCall(
          name,
          on: .codebase,
          at: arguments.location
        )
      )
      _ = try requireIndexProvider(at: arguments.location)
      return .projectIndex(index)
    case .conformers, .directConformers, .references, .definitions,
         .occurrences:
      let index = try projectIndex(
        over: codebase,
        arguments,
        declaredBy: try indexQueryCall(
          name,
          on: .codebase,
          at: arguments.location
        )
      )
      let provider = try requireIndexProvider(at: arguments.location)
      let references = try await indexReferences(
        name,
        of: try arguments.string(at: 0),
        in: index,
        from: provider,
        at: arguments.location
      )
      return .array(
        references.map {
          RuntimeValue.model(.indexReference($0))
        }
      )
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not supported in portable rules",
        location: arguments.location
      )
    }
  }

  private func ignoredTargets(
    _ arguments: RuntimeArguments,
    method: SupportedAPI.Method
  ) throws(RuntimeError) -> [String] {
    if arguments.values.isEmpty { return [] }
    try arguments.requireLabels([.ignoring], for: method)
    return try arguments.strings(at: 0)
  }

  func projectIndexMethod(
    _ name: SupportedAPI.Method,
    index: RuntimeProjectIndex,
    arguments: RuntimeArguments
  ) async throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels(
      try indexQueryCall(
        name, on: .projectIndex, at: arguments.location
      ).leadingLabels,
      for: name
    )
    let provider = try requireIndexProvider(at: arguments.location)
    let symbol = try arguments.string(at: 0)
    let values = try await indexReferences(
      name,
      of: symbol,
      in: index,
      from: provider,
      at: arguments.location
    )
    return .array(values.map { RuntimeValue.model(.indexReference($0)) })
  }

  private func indexReferences(
    _ name: SupportedAPI.Method,
    of symbol: String,
    in index: RuntimeProjectIndex,
    from provider: any RuntimeIndexProvider,
    at location: DeclarationLocation
  ) async throws(RuntimeError) -> [RuntimeIndexReference] {
    guard let query = RuntimeIndexQuery(rawValue: name.rawValue) else {
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported index query",
        location: location
      )
    }
    return try await reportingFailures(at: location) {
      try await provider.references(query, of: symbol, in: index)
    }
  }

  func reportingFailures<Value, Failure: Error>(
    at location: DeclarationLocation,
    _ operation: () async throws(Failure) -> Value
  ) async throws(RuntimeError) -> Value {
    do {
      return try await operation()
    } catch {
      throw RuntimeError(wrapping: error, at: location)
    }
  }

  func indexQueryCall(
    _ name: SupportedAPI.Method,
    on receiver: SupportedAPI.RuntimeReceiver,
    at location: DeclarationLocation
  ) throws(RuntimeError) -> SupportedAPI.RuntimeCallArguments {
    guard let member = SupportedAPI.Member(rawValue: name.rawValue),
          let api = SupportedAPI.runtimeMethod(named: member, on: receiver),
          case let .method(call) = api.kind
    else {
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported index query",
        location: location
      )
    }
    return call.arguments
  }

  func projectIndex(
    over codebase: Codebase,
    _ arguments: RuntimeArguments,
    declaredBy call: SupportedAPI.RuntimeCallArguments
  ) throws(RuntimeError) -> RuntimeProjectIndex {
    let leadingLabels = call.leadingLabels
    guard arguments.values.count >= leadingLabels.count else {
      throw RuntimeError(
        message: "the index query is missing a required argument",
        location: arguments.location
      )
    }
    let tail = arguments.values.indices.dropFirst(leadingLabels.count).map {
      (label: arguments.label(at: $0), value: arguments.values[$0].value)
    }
    guard leadingLabels.indices.allSatisfy({
      arguments.label(at: $0) == leadingLabels[$0]
    }) else {
      throw RuntimeError(
        message: "this index query starts with "
          + leadingLabels.map { "'\($0.rawValue):'" }
          .joined(separator: ", "),
        location: arguments.location
      )
    }
    let optionalLabels = call.trailingLabels
    guard tail.allSatisfy({ argument in
      argument.label.map(optionalLabels.contains) == true
    }) else {
      throw RuntimeError(
        message: "this index query takes only "
          + optionalLabels.map { "'\($0.rawValue):'" }
          .joined(separator: " and "),
        location: arguments.location
      )
    }
    guard Set(tail.compactMap(\.label)).count == tail.count else {
      throw RuntimeError(
        message: "this index query repeats an argument label",
        location: arguments.location
      )
    }
    func strings(label: SupportedAPI
      .ArgumentLabel) throws(RuntimeError) -> Set<String>?
    {
      guard let value = tail.first(where: { $0.label == label })?.value else {
        return nil
      }
      switch value {
      case .optional(nil): return nil
      case let .optional(.some(.array(values))), let .array(values):
        return Set(
          try values.map { value throws(RuntimeError) in
            guard case let .string(value) = value else {
              throw RuntimeError(
                message: "'\(label.rawValue)' must contain only strings",
                location: arguments.location
              )
            }
            return value
          }
        )
      default:
        throw RuntimeError(
          message: "'\(label.rawValue)' must be Set<String> or nil",
          location: arguments.location
        )
      }
    }
    return RuntimeProjectIndex(
      codebase: codebase,
      modules: try strings(label: .modules),
      unitOutputFiles: try strings(label: .unitOutputFiles)
    )
  }

  func requireIndexProvider(
    at location: DeclarationLocation
  ) throws(RuntimeError) -> any RuntimeIndexProvider {
    guard let indexProvider else {
      throw RuntimeError(
        message: "index queries need a completed build. "
          +
          "Run these rules with 'bylaws lint' after building, without --source-only.",
        location: location
      )
    }
    return indexProvider
  }
}
