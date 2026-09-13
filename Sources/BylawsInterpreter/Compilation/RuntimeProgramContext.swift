import BylawsCore
import BylawsSemantics

actor RuntimeProgramContext {
  private let file: ParsedRulesFile
  private let sourceModules: [RuntimeSourceModule]
  private let importedModuleNames: [String]
  private let indexProvider: (any RuntimeIndexProvider)?
  private var environmentEntry: MemoisedTask<RuntimeEnvironment, RuntimeError>?

  init(
    file: ParsedRulesFile,
    sourceModules: [RuntimeSourceModule] = [],
    importedModuleNames: [String] = [],
    indexProvider: (any RuntimeIndexProvider)?
  ) {
    self.file = file
    self.sourceModules = sourceModules
    self.importedModuleNames = importedModuleNames
    self.indexProvider = indexProvider
  }

  func resolvedEnvironment() async throws(RuntimeError) -> RuntimeEnvironment {
    let file = file
    let sourceModules = sourceModules
    let importedModuleNames = importedModuleNames
    let indexProvider = indexProvider
    return try await MemoisedTask.value(
      name: "bylaws: resolve rule environment",
      lookup: { environmentEntry },
      insert: { environmentEntry = $0 },
      remove: { environmentEntry = nil }
    ) { () async throws(RuntimeError) in
      try await Self.makeEnvironment(
        file: file,
        sourceModules: sourceModules,
        importedModuleNames: importedModuleNames,
        indexProvider: indexProvider
      )
    }
  }

  func resolvedRules() async throws(RuntimeError) -> [RuntimeRule] {
    let environment = try await resolvedEnvironment()
    var rules: [RuntimeRule] = []
    for name in file.runtimeRuleBindings {
      guard case let .array(values) = environment[name] else {
        throw RuntimeError(
          message: "'\(name)' must be [Rule]",
          location: bindingLocation(named: name)
        )
      }
      for value in values {
        guard case let .rule(rule) = value else {
          throw RuntimeError(
            message: "'\(name)' must contain only Rule values",
            location: bindingLocation(named: name)
          )
        }
        rules.append(rule)
      }
    }
    return rules
  }

  private func bindingLocation(named name: String) -> DeclarationLocation {
    file.runtimeBindings.first { $0.name == name }?.location
      ?? DeclarationLocation.start(of: file.path)
  }

  private static func makeEnvironment(
    file: ParsedRulesFile,
    sourceModules: [RuntimeSourceModule],
    importedModuleNames: [String],
    indexProvider: (any RuntimeIndexProvider)?
  ) async throws(RuntimeError) -> RuntimeEnvironment {
    var exportsByModule: [String: RuntimeEnvironment] = [:]
    for module in sourceModules {
      var imported = RuntimeEnvironment()
      for name in module.importedModuleNames {
        if let exports = exportsByModule[name] {
          imported.merge(exports)
        }
      }
      let environment = try await makeEnvironment(
        file: module.file,
        importing: imported,
        indexProvider: indexProvider
      )
      exportsByModule[module.name] = environment.exporting(
        module.exportedNames
      )
    }

    var imported = RuntimeEnvironment()
    for name in importedModuleNames {
      if let exports = exportsByModule[name] {
        imported.merge(exports)
      }
    }
    return try await makeEnvironment(
      file: file,
      importing: imported,
      indexProvider: indexProvider
    )
  }

  private static func makeEnvironment(
    file: ParsedRulesFile,
    importing imported: RuntimeEnvironment,
    indexProvider: (any RuntimeIndexProvider)?
  ) async throws(RuntimeError) -> RuntimeEnvironment {
    var environment = imported
    for (name, codebase) in file.codebases {
      environment.bind(.codebase(codebase), to: name)
    }
    for (name, layering) in file.layerings {
      environment.bind(.layering(layering), to: name)
    }
    for function in file.runtimeFunctions {
      environment.bind(
        .function(RuntimeFunction(definition: function, captures: nil)),
        to: function.name
      )
    }

    var pending = file.runtimeBindings
    var state = RuntimeEvaluationState(limits: .standard)
    while !pending.isEmpty {
      var deferred: [RuntimeGlobalBinding] = []
      var firstFailure: RuntimeError?
      var madeProgress = false
      for binding in pending {
        let evaluator = RuntimeEvaluator(
          globals: environment,
          indexProvider: indexProvider
        )
        do throws(RuntimeError) {
          let value = try await evaluator.evaluate(
            binding.expression,
            in: environment,
            state: &state
          )
          let coerced: RuntimeValue
          if let type = binding.type {
            guard let typedValue = value.coerced(to: type) else {
              throw RuntimeError(
                message: "'\(binding.name)' must be \(type.writtenName)",
                location: binding.location
              )
            }
            coerced = typedValue
          } else {
            coerced = value
          }
          environment.bind(coerced, to: binding.name)
          madeProgress = true
        } catch where error.kind == .undeclaredName {
          deferred.append(binding)
          firstFailure = firstFailure ?? error
        }
      }
      if deferred.isEmpty {
        return environment.resolvingRuleCaptures(
          excluding: Set(file.runtimeRuleBindings)
        )
      }
      guard madeProgress else {
        guard let firstFailure else {
          throw RuntimeError(
            message: "top-level bindings contain unresolved references",
            location: pending[0].location
          )
        }
        throw firstFailure
      }
      pending = deferred
    }
    return environment.resolvingRuleCaptures(
      excluding: Set(file.runtimeRuleBindings)
    )
  }
}
