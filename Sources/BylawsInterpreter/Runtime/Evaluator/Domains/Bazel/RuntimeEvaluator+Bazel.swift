import BylawsCore

extension RuntimeEvaluator {
  func bazelTargetMember(
    _ name: SupportedAPI.Member,
    _ target: BazelGraph.Target
  ) -> RuntimeValue? {
    switch name {
    case .label: .string(target.label)
    case .description: .string(target.description)
    case .configuration:
      .optional(target.configuration.map { .model(.bazelConfiguration($0)) })
    case .ruleClass: optionalString(target.ruleClass)
    case .tags: .array(target.tags.map(RuntimeValue.string))
    default: nil
    }
  }

  func bazelConfigurationMember(
    _ name: SupportedAPI.Member,
    _ configuration: BazelGraph.Configuration
  ) -> RuntimeValue? {
    switch name {
    case .checksum: return .string(configuration.checksum)
    case .isTool: return .boolean(configuration.isTool)
    case .buildOptions:
      var groups: [RuntimeDictionaryKey: RuntimeValue] = [:]
      for (group, options) in configuration.buildOptions {
        var values: [RuntimeDictionaryKey: RuntimeValue] = [:]
        for (name, value) in options {
          values[.string(name)] = .string(value)
        }
        groups[.string(group)] = .dictionary(values)
      }
      return .dictionary(groups)
    default: return nil
    }
  }

  func bazelDependencies(
    _ name: SupportedAPI.Method,
    graph: BazelGraph,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    try arguments.requireLabels([.of], for: name)
    guard case let .model(.bazelTarget(target)) = try arguments.value(at: 0)
    else {
      throw RuntimeError(
        message: "\(name.rawValue) takes one BazelGraph.Target",
        location: arguments.location
      )
    }
    let dependencies = if name == .directTargetDependencies {
      graph.directTargetDependencies(of: target)
    } else {
      graph.transitiveTargetDependencies(of: target)
    }
    return modelArray(dependencies, RuntimeModelValue.bazelTarget)
  }
}
