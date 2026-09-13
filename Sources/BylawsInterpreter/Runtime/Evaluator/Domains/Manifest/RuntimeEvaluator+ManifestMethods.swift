import BylawsSemantics

extension RuntimeEvaluator {
  func manifestMethod(
    _ name: SupportedAPI.Method,
    manifest: PackageManifest,
    arguments: RuntimeArguments
  ) throws(RuntimeError) -> RuntimeValue {
    switch name {
    case .dependencies:
      try arguments.requireLabels([.named], for: name)
      return manifestList(manifest
        .dependencies(named: try arguments.string(at: 0)))
      {
        .model(.manifest(.dependency($0)))
      }
    case .products:
      switch arguments.label(at: 0) {
      case .named:
        try arguments.requireLabels([.named], for: name)
        return manifestList(manifest
          .products(named: try arguments.string(at: 0)))
        {
          .model(.manifest(.product($0)))
        }
      case .containing:
        try arguments.requireLabels([.containing], for: name)
        return manifestList(
          manifest.products(containing: try manifestTarget(arguments, at: 0))
        ) { .model(.manifest(.product($0))) }
      default:
        throw unsupportedManifestArguments(name, at: arguments.location)
      }
    case .targets:
      if arguments.label(at: 0) == .named {
        try arguments.requireLabels([.named], for: name)
        return manifestList(manifest
          .targets(named: try arguments.string(at: 0)))
        {
          .model(.manifest(.target($0)))
        }
      }
      let includesConditional = try includesConditionalDependencies(
        arguments,
        for: name
      )
      return manifestList(
        manifest.targets(
          includingConditionalDependencies: includesConditional
        )
      ) { .model(.manifest(.target($0))) }
    case .directTargetDependencies:
      return manifestList(
        manifest.directTargetDependencies(
          of: try manifestTarget(arguments, at: 0),
          includingConditionalDependencies: try includesConditionalDependencies(
            arguments,
            for: name,
            after: .of
          )
        )
      ) { .model(.manifest(.target($0))) }
    case .transitiveTargetDependencies:
      return manifestList(
        manifest.transitiveTargetDependencies(
          of: try manifestTarget(arguments, at: 0),
          includingConditionalDependencies: try includesConditionalDependencies(
            arguments,
            for: name,
            after: .of
          )
        )
      ) { .model(.manifest(.target($0))) }
    case .testTargets:
      let target = try manifestTarget(arguments, at: 0)
      switch arguments.label(at: 0) {
      case .dependingDirectlyOn:
        return manifestList(
          manifest.testTargets(
            dependingDirectlyOn: target,
            includingConditionalDependencies: try includesConditionalDependencies(
              arguments,
              for: name,
              after: .dependingDirectlyOn
            )
          )
        ) { .model(.manifest(.target($0))) }
      case .dependingOn:
        return manifestList(
          manifest.testTargets(
            dependingOn: target,
            includingConditionalDependencies: try includesConditionalDependencies(
              arguments,
              for: name,
              after: .dependingOn
            )
          )
        ) { .model(.manifest(.target($0))) }
      default:
        throw unsupportedManifestArguments(name, at: arguments.location)
      }
    default:
      throw RuntimeError(
        message: "'\(name.rawValue)' is not a supported PackageManifest method",
        location: arguments.location
      )
    }
  }

  private func manifestTarget(
    _ arguments: RuntimeArguments,
    at index: Int
  ) throws(RuntimeError) -> PackageManifest.Target {
    guard case let .model(.manifest(.target(target))) = try arguments
      .value(at: index)
    else {
      throw RuntimeError(
        message: "argument \(index + 1) must be PackageManifest.Target",
        location: arguments.location
      )
    }
    return target
  }

  private func includesConditionalDependencies(
    _ arguments: RuntimeArguments,
    for method: SupportedAPI.Method,
    after leadingLabel: SupportedAPI.ArgumentLabel? = nil
  ) throws(RuntimeError) -> Bool {
    let labels: [SupportedAPI.ArgumentLabel?] = if let leadingLabel {
      arguments.values.count == 1
        ? [leadingLabel]
        : [leadingLabel, .includingConditionalDependencies]
    } else {
      arguments.values.isEmpty ? [] : [.includingConditionalDependencies]
    }
    try arguments.requireLabels(labels, for: method)
    let conditionalArgumentIndex = leadingLabel == nil ? 0 : 1
    guard arguments.values.indices.contains(conditionalArgumentIndex) else {
      return false
    }
    return try arguments.boolean(at: conditionalArgumentIndex)
  }

  private func unsupportedManifestArguments(
    _ method: SupportedAPI.Method,
    at location: DeclarationLocation
  ) -> RuntimeError {
    RuntimeError(
      message: "'\(method.rawValue)' has unsupported PackageManifest arguments",
      location: location
    )
  }
}
