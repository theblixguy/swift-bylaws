import BylawsSemantics

enum RuntimeProgramResolver {
  @discardableResult
  static func resolve(
    _ file: inout ParsedRulesFile,
    importing importedSymbols: [String: SupportedAPI.RuntimeType] = [:]
  ) -> RuntimeProgramSymbols {
    guard !file.runtimeBindings.isEmpty || !file.runtimeFunctions.isEmpty
    else { return RuntimeProgramSymbols(all: importedSymbols, exported: [:]) }

    var environment = importedSymbols
    for name in file.codebases.keys { environment[name] = .codebase }
    for name in file.layerings.keys { environment[name] = .layering }
    for function in file.runtimeFunctions {
      environment[function.name] = .function(function.runtimeType)
    }
    for binding in file.runtimeBindings {
      if let type = binding.type {
        environment[binding.name] = type
      }
    }

    var unresolved = file.runtimeBindings.filter { $0.type == nil }
    while !unresolved.isEmpty {
      var deferred: [RuntimeGlobalBinding] = []
      var madeProgress = false
      for binding in unresolved {
        var resolver = RuntimeTypeResolver(
          environment: environment,
          reportsDiagnostics: false
        )
        let type = resolver.resolve(binding.expression)
        if type == .unknown {
          deferred.append(binding)
        } else {
          environment[binding.name] = type
          madeProgress = true
        }
      }
      guard madeProgress else { break }
      unresolved = deferred
    }

    var resolver = RuntimeTypeResolver(environment: environment)
    for binding in file.runtimeBindings {
      let expected = binding.type
      let resolved = resolver.resolve(binding.expression, expected: expected)
      if let expected {
        resolver.require(
          resolved,
          toMatch: expected,
          subject: "'\(binding.name)'",
          at: binding.location
        )
      }
    }
    for function in file.runtimeFunctions {
      resolver.resolve(function)
    }

    if !resolver.constructors.isEmpty {
      let resolution = RuntimeConstructorResolution(constructors: resolver
        .constructors)
      file.runtimeBindings = file.runtimeBindings.map {
        RuntimeGlobalBinding(
          name: $0.name, type: $0.type,
          expression: resolution.resolve($0.expression),
          location: $0.location, access: $0.access
        )
      }
      file.runtimeFunctions = file.runtimeFunctions.map {
        RuntimeFunctionDefinition(
          name: $0.name, parameters: $0.parameters, returnType: $0.returnType,
          isAsync: $0.isAsync, isThrowing: $0.isThrowing,
          body: resolution.resolve($0.body), location: $0.location,
          access: $0.access
        )
      }
    }

    if !resolver.diagnostics.isEmpty {
      file.diagnostics.append(contentsOf: resolver.diagnostics)
      file.runtimeRuleBindings.removeAll()
    }
    let exportedNames = Set(
      file.runtimeFunctions.filter { $0.access == .exported }.map(\.name)
        + file.runtimeBindings.filter { $0.access == .exported }.map(\.name)
    )
    return RuntimeProgramSymbols(
      all: environment,
      exported: environment.filter { exportedNames.contains($0.key) }
    )
  }
}

struct RuntimeProgramSymbols: Sendable {
  let all: [String: SupportedAPI.RuntimeType]
  let exported: [String: SupportedAPI.RuntimeType]
}
