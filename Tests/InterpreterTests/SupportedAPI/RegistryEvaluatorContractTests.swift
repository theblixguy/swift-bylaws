import BylawsCore
import BylawsSemantics
import BylawsTestSupport
import SwiftSyntax
import Testing
@testable import BylawsInterpreter

@Suite("Registry and evaluator contract")
struct RegistryEvaluatorContractTests {
  @Test("Every registered model property evaluates to its declared type")
  func propertiesEvaluateToDeclaredTypes() async throws {
    let samples = try await ModelSamples()
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var problems: [String] = []

    for api in SupportedAPI.runtimeMembers {
      guard case let .property(.fixed(expected)) = api.kind else { continue }
      for receiver in api.receivers {
        guard case let .model(modelType) = receiver else { continue }
        let member = "\(modelType.rawValue).\(api.name.rawValue)"
        let values = samples.values(of: modelType)
        if values.isEmpty {
          problems
            .append("\(member): no sample value for \(modelType.rawValue)")
          continue
        }
        var provesType = false
        for value in values {
          guard let result = evaluator.modelMember(api.name, of: value)
          else {
            problems.append("\(member): the evaluator has no implementation")
            continue
          }
          if !result.hasRuntimeType(expected) {
            problems.append(
              "\(member): declared \(expected.writtenName), evaluated to \(result)"
            )
          } else if result.provesNestedType {
            provesType = true
          }
        }
        if !provesType {
          problems.append(
            "\(member): sample values do not prove \(expected.writtenName)"
          )
        }
      }
    }

    let report = problems.uniqued().joined(separator: "\n")
    #expect(problems.isEmpty, Comment(rawValue: report))
  }

  @Test("Every registered model method reaches an evaluator arm")
  func methodsReachEvaluatorArms() async throws {
    let samples = try await ModelSamples()
    let evaluator = RuntimeEvaluator(globals: RuntimeEnvironment())
    var state = RuntimeEvaluationState(limits: .standard)
    var problems: [String] = []

    for api in SupportedAPI.runtimeMembers {
      guard case let .method(call) = api.kind else { continue }
      for receiver in api.receivers {
        guard case let .model(modelType) = receiver,
              let value = samples.values(of: modelType).first
        else { continue }
        let member = "\(modelType.rawValue).\(api.name.rawValue)"
        do {
          _ = try await evaluator.invoke(
            method: call.method,
            of: .model(value),
            arguments: RuntimeArguments(values: [], location: .start(of: "")),
            state: &state
          )
        } catch where error.message.contains("is not a supported") {
          problems.append("\(member): \(error.message)")
        } catch {}
      }
    }

    let report = problems.uniqued().joined(separator: "\n")
    #expect(problems.isEmpty, Comment(rawValue: report))
  }

  @Test("Every index query a rule may write names one registry entry")
  func indexQueriesMatchTheRegistry() {
    let registered = Set(
      SupportedAPI.runtimeMembers
        .filter { api in
          api.receivers.contains(.projectIndex)
            && { if case .method = api.kind { true } else { false } }()
        }
        .map(\.name.rawValue)
    )

    #expect(registered == Set(RuntimeIndexQuery.allCases.map(\.rawValue)))
    for query in RuntimeIndexQuery.allCases {
      let method = SupportedAPI.Member(rawValue: query.rawValue).flatMap {
        SupportedAPI.runtimeMethod(named: $0, on: .codebase)
      }
      #expect(method != nil, "\(query.rawValue) names no codebase method")
    }
  }

  @Test("Every model type with registered properties has a sample")
  func everyModelReceiverHasSample() async throws {
    let samples = try await ModelSamples()
    let receivers = Set(SupportedAPI.runtimeMembers.flatMap { api in
      api.receivers.compactMap { receiver -> SupportedAPI.ModelType? in
        if case let .model(type) = receiver { return type }
        return nil
      }
    })
    let missing = receivers.filter { samples.values(of: $0).isEmpty }
    #expect(missing.isEmpty, "\(missing.map(\.rawValue).sorted())")
  }
}

private struct ModelSamples {
  private var storage: [SupportedAPI.ModelType: [RuntimeModelValue]] = [:]

  init() async throws {
    try await addSemanticSamples()
    try addExpressionSamples()
    addManifestSamples()
    addGraphAndIndexSamples()
    let bazelGraph = try await Codebase(root: .sources([
      "graph.json": BazelGraphMock.json,
    ])).bazelGraph(from: "graph.json")
    add(.bazelGraph(bazelGraph))
    add(bazelGraph.targets, as: RuntimeModelValue.bazelTarget)
    add(
      bazelGraph.targets.compactMap(\.configuration),
      as: RuntimeModelValue.bazelConfiguration
    )
    for value in try await ContractMocks.checkResults() {
      add(.check(value))
    }
  }

  func values(of type: SupportedAPI.ModelType) -> [RuntimeModelValue] {
    storage[type] ?? []
  }

  private mutating func add(_ value: RuntimeModelValue) {
    storage[value.modelType, default: []].append(value)
  }

  private mutating func add<S: Sequence>(
    _ values: S,
    as wrap: (S.Element) -> RuntimeModelValue
  ) {
    for value in values { add(wrap(value)) }
  }

  private mutating func add<Element>(
    _ list: ManifestList<Element>,
    as wrap: (Element) -> RuntimeModelValue
  ) {
    add(list.possibleValues, as: wrap)
    add(list.unresolvedValues, as: { .manifest(.unresolvedValue($0)) })
  }
}

extension ModelSamples {
  private mutating func addExpressionSamples() throws {
    let file = try FileCollector.collect(
      source: #"""
      func check() {
        var enabled = false
        enabled = true
        log("text", "\(user, privacy: .public)", false, 0, 1.5, nil,
            Store.save(value: value), ["key": value], [value])
      }
      """#,
      path: "/virtual/Expressions.swift"
    )
    let arguments = file.calls.flatMap(\.arguments)
    add(.sourceFile(file))
    add(file.assignments, as: RuntimeModelValue.sourceAssignment)
    add(file.variableBindings, as: RuntimeModelValue.variableBinding)
    add(file.expressions, as: RuntimeModelValue.sourceExpression)
    add(
      file.expressions.flatMap(\.enclosingDeclarations),
      as: RuntimeModelValue.enclosingDeclaration
    )
    add(arguments, as: RuntimeModelValue.callArgument)
    var expressions = arguments.compactMap(\.expression)
    while let expression = expressions.popLast() {
      add(.sourceExpression(expression))
      let arguments = (expression.arguments ?? []) + expression.interpolations
        .flatMap(\.self)
      add(arguments, as: RuntimeModelValue.expressionArgument)
      expressions += arguments.map(\.expression)
      expressions += expression.arrayElements ?? []
      let entries = expression.dictionaryElements ?? []
      add(entries, as: RuntimeModelValue.dictionaryElement)
      expressions += entries.flatMap { [$0.key, $0.value] }
      if let base = expression.base { expressions.append(base) }
      if let called = expression.calledExpression { expressions.append(called) }
    }
  }

  private mutating func addSemanticSamples() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/App/Widget.swift": ContractMocks.semanticSource,
    ]))
    let file = try #require(await codebase.files.first)
    add(.sourceFile(file))
    add(try await codebase.classes, as: RuntimeModelValue.classDeclaration)
    add(try await codebase.actors, as: RuntimeModelValue.actor)
    add(try await codebase.structs, as: RuntimeModelValue.structDeclaration)
    add(try await codebase.enums, as: RuntimeModelValue.enumDeclaration)
    add(try await codebase.types, as: RuntimeModelValue.nominalType)
    add(try await codebase.protocols, as: RuntimeModelValue.protocolDeclaration)
    add(
      try await codebase.extensions,
      as: RuntimeModelValue.extensionDeclaration
    )
    add(try await codebase.functions, as: RuntimeModelValue.function)
    add(try await codebase.properties, as: RuntimeModelValue.property)
    add(try await codebase.initializers, as: RuntimeModelValue.initializer)
    add(try await codebase.imports, as: RuntimeModelValue.importDeclaration)
    add(
      try await codebase.typealiases,
      as: RuntimeModelValue.typealiasDeclaration
    )
    add(try await codebase.calls, as: RuntimeModelValue.functionCall)
    for function in try await codebase.functions {
      add(function.parameters, as: RuntimeModelValue.parameter)
      add(function.genericParameters, as: RuntimeModelValue.genericParameter)
      if let returnType = function
        .returnType { add(.typeReference(returnType)) }
    }
    for property in try await codebase.properties {
      if let type = property.type { add(.typeReference(type)) }
    }
    for type in try await codebase.types {
      add(type.attributes, as: RuntimeModelValue.attribute)
      add(type.genericParameters, as: RuntimeModelValue.genericParameter)
    }
    for enumeration in try await codebase.enums {
      add(enumeration.cases, as: RuntimeModelValue.enumCase)
    }
    let widget = try #require(await codebase.classes.first)
    add(.offender(Offender(
      description: widget.description, name: widget.name,
      location: widget.location, affectedPath: "/project/Views",
      requirement: "be final"
    )))
    try file.withSyntax { syntax in
      add(.syntaxSourceFile(syntax))
      let classes = syntax.statements.compactMap {
        $0.item.as(ClassDeclSyntax.self)
      }
      let classSyntax = try #require(classes.first)
      add(.syntaxClass(classSyntax))
      add(.syntaxMemberBlock(classSyntax.memberBlock))
      add(.syntaxToken(classSyntax.name))
      add(.syntaxToken(classSyntax.classKeyword))
      if let token = classSyntax.firstToken(viewMode: .sourceAccurate),
         !token.leadingTrivia.isEmpty
      {
        add(.syntaxToken(token))
      }
      add(
        classSyntax.leadingTrivia.pieces,
        as: RuntimeModelValue.syntaxTriviaPiece
      )
      add(
        classSyntax.name.trailingTrivia.pieces,
        as: RuntimeModelValue.syntaxTriviaPiece
      )
    }
  }
}

extension ModelSamples {
  private mutating func addManifestSamples() {
    let manifest = PackageManifest(source: ContractMocks.manifestSource)
    add(.packageManifest(manifest))
    let unresolvedManifest = PackageManifest(
      source: ContractMocks.unresolvedManifestSource
    )
    add(.packageManifest(unresolvedManifest))
    if let toolsVersion = manifest.toolsVersion {
      add(.manifest(.toolsVersion(toolsVersion)))
    }
    add(manifest.platforms, as: { .manifest(.platform($0)) })
    for platform in manifest.platforms.possibleValues {
      add(.manifest(.platformVersion(platform.minimumVersion)))
    }
    add(manifest.products, as: { .manifest(.product($0)) })
    add(manifest.traits, as: { .manifest(.trait($0)) })
    add(manifest.dependencies, as: { .manifest(.dependency($0)) })
    for dependency in manifest.dependencies.possibleValues {
      add(.manifest(.dependencyRequirement(dependency.requirement)))
      addVersions(of: dependency.requirement)
      add(
        dependency.traits,
        as: { .manifest(.dependencyTraitSelection($0)) }
      )
      for selection in dependency.traits.possibleValues {
        if let condition = selection.condition {
          add(.manifest(.condition(condition)))
        }
      }
    }
    add(manifest.targets, as: { .manifest(.target($0)) })
    for target in manifest.targets.possibleValues {
      addTarget(target)
    }
    add(
      manifest.unresolvedValues,
      as: { .manifest(.unresolvedValue($0)) }
    )
    add(
      unresolvedManifest.unresolvedValues,
      as: { .manifest(.unresolvedValue($0)) }
    )
  }

  private mutating func addVersions(
    of requirement: PackageManifest.Dependency.Requirement
  ) {
    switch requirement {
    case let .exact(version), let .upToNextMajor(version),
         let .upToNextMinor(version):
      add(.manifest(.version(version)))
    case let .range(lower, upper), let .closedRange(lower, upper):
      add(.manifest(.version(lower)))
      add(.manifest(.version(upper)))
    case .branch, .revision, .local:
      break
    }
  }

  private mutating func addTarget(_ target: PackageManifest.Target) {
    add(target.dependencies, as: { .manifest(.targetDependency($0)) })
    for dependency in target.dependencies.possibleValues {
      if let condition = dependency.condition {
        add(.manifest(.condition(condition)))
      }
    }
    add(.manifest(.targetSourceSelection(target.sources)))
    add(target.resources, as: { .manifest(.targetResource($0)) })
    add(target.buildSettings, as: { .manifest(.targetSetting($0)) })
    for setting in target.buildSettings.possibleValues {
      if let condition = setting.condition {
        add(.manifest(.condition(condition)))
      }
    }
    add(target.plugins, as: { .manifest(.targetPluginUsage($0)) })
    if let binarySource = target.binarySource {
      add(.manifest(.binarySource(binarySource)))
    }
    add(
      target.providers,
      as: { .manifest(.targetSystemPackageProvider($0)) }
    )
    if let capability = target.pluginCapability {
      add(.manifest(.pluginCapability(capability)))
      if case let .command(intent, permissions) = capability {
        add(.manifest(.pluginIntent(intent)))
        for permission in permissions {
          add(.manifest(.pluginPermission(permission)))
          if case let .allowNetworkConnections(scope, _) = permission {
            add(.manifest(.networkScope(scope)))
            switch scope {
            case let .local(ports), let .all(ports):
              add(.manifest(.networkPorts(ports)))
            case .none, .docker, .unixDomainSocket:
              break
            }
          }
        }
      }
    }
    add(target.unresolvedValues, as: { .manifest(.unresolvedValue($0)) })
  }
}

extension ModelSamples {
  private mutating func addGraphAndIndexSamples() {
    let app = ImportGraph.Target(name: "App", importedBy: [], imports: ["Core"])
    let core = ImportGraph.Target(
      name: "Core",
      importedBy: ["App"],
      imports: []
    )
    let graph = ImportGraph(targets: [app, core])
    add(.importGraph(graph))
    add(graph.targets, as: RuntimeModelValue.importGraphTarget)

    let symbol = RuntimeIndexSymbol(
      usr: "s:3App6WidgetC",
      name: "Widget",
      kind: .class
    )
    add(.indexSymbol(symbol))
    add(.indexReference(RuntimeIndexReference(
      symbol: symbol, module: "App", file: "/Sources/App/Widget.swift",
      line: 5, column: 20, roles: [.definition, .reference]
    )))
  }
}

extension Sequence where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}

extension RuntimeValue {
  fileprivate var provesNestedType: Bool {
    switch self {
    case .optional(nil):
      false
    case let .optional(.some(value)):
      value.provesNestedType
    case let .array(values), let .set(values):
      values.contains(where: \.provesNestedType)
    case let .manifestList(list):
      list.possibleValues.contains(where: \.provesNestedType)
    default:
      true
    }
  }
}
