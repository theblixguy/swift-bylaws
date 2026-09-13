extension PackageManifest {
  /// Returns the direct local target dependencies of `target`.
  ///
  /// The result excludes conditional dependencies by default. Set
  /// `includingConditionalDependencies` to `true` to include them in
  /// ``ManifestList/conditionalValues``.
  public func directTargetDependencies(
    of target: Target,
    includingConditionalDependencies: Bool = false
  ) -> ManifestList<Target> {
    TargetLookup(targets).dependencies(
      of: target,
      includingConditionalDependencies: includingConditionalDependencies
    )
  }

  /// Returns all local target dependencies of `target`.
  ///
  /// The result excludes conditional dependencies by default. Set
  /// `includingConditionalDependencies` to `true` to include their targets in
  /// ``ManifestList/conditionalValues``.
  public func transitiveTargetDependencies(
    of target: Target,
    includingConditionalDependencies: Bool = false
  ) -> ManifestList<Target> {
    TargetDependencyGraph(
      self,
      root: target,
      includingConditionalDependencies: includingConditionalDependencies
    ).dependencies(of: target, transitively: true)
  }

  /// Returns test targets that directly declare a dependency on `target`.
  public func testTargets(
    dependingDirectlyOn target: Target,
    includingConditionalDependencies: Bool = false
  ) -> ManifestList<Target> {
    targetsDepending(
      on: target,
      transitively: false,
      includingConditionalDependencies: includingConditionalDependencies
    )
  }

  /// Returns test targets with a dependency path to `target`.
  public func testTargets(
    dependingOn target: Target,
    includingConditionalDependencies: Bool = false
  ) -> ManifestList<Target> {
    targetsDepending(
      on: target,
      transitively: true,
      includingConditionalDependencies: includingConditionalDependencies
    )
  }

  /// Returns targets included in a library or executable product.
  public func targets(
    includingConditionalDependencies: Bool = false
  ) -> ManifestList<Target> {
    let graph = TargetDependencyGraph(
      self,
      includingConditionalDependencies: includingConditionalDependencies
    )
    var knownRoots: [String] = []
    var possibleRoots: [String] = []
    var unresolved = products.unresolvedValues

    func include(_ product: Product, conditional productIsConditional: Bool) {
      if case .plugin = product.kind { return }
      unresolved.append(contentsOf: product.targetNames.unresolvedValues)
      for name in product.targetNames.knownValues {
        let roots = graph.targets(named: name)
        if roots.possibleValues.isEmpty {
          unresolved.append(
            UnresolvedValue(
              field: "products.\(product.name).targetNames",
              expression: "missing target \(name)"
            )
          )
        }
        possibleRoots += roots.possibleValues.map(\.name)
        if !productIsConditional {
          knownRoots += roots.knownValues.map(\.name)
        }
      }
      for name in product.targetNames.conditionalValues {
        let roots = graph.targets(named: name)
        possibleRoots += roots.possibleValues.map(\.name)
      }
    }

    for product in products.knownValues {
      include(product, conditional: false)
    }
    for product in products.conditionalValues {
      include(product, conditional: true)
    }
    for target in targets.knownValues where target.kind == .executable {
      knownRoots.append(target.name)
      possibleRoots.append(target.name)
    }
    for target in targets.conditionalValues where target.kind == .executable {
      possibleRoots.append(target.name)
    }

    let knownNames = graph.orderedClosure(
      from: knownRoots,
      using: graph.unconditional
    )
    let possibleNames = graph.orderedClosure(
      from: possibleRoots,
      using: graph.possible
    )
    unresolved.append(contentsOf: graph.unresolvedValues(
      from: possibleRoots,
      reachableNames: possibleNames
    ))
    let knownNameSet = Set(knownNames)
    return ManifestList(
      knownValues: graph.targets(named: knownNames),
      conditionalValues: graph.targets(named: possibleNames.filter {
        !knownNameSet.contains($0)
      }),
      unresolvedValues: unresolved
    )
  }

  private func targetsDepending(
    on target: Target,
    transitively: Bool,
    includingConditionalDependencies: Bool
  ) -> ManifestList<Target> {
    let graph = TargetDependencyGraph(
      self,
      includingConditionalDependencies: includingConditionalDependencies
    )
    let knownDependants = Set(
      graph.relatedNames(
        to: target.name,
        direction: .reverse,
        transitively: transitively,
        using: graph.unconditional
      )
    )
    let possibleDependants = Set(
      graph.relatedNames(
        to: target.name,
        direction: .reverse,
        transitively: transitively,
        using: graph.possible
      )
    )
    let testTargets = targets.possibleValues.filter(\.isTest)
    let unresolved = graph.unresolvedValues(
      from: testTargets.map(\.name),
      transitively: transitively
    )
    var known: [Target] = []
    var conditional: [Target] = []

    func inspect(_ testTarget: Target, conditional targetIsConditional: Bool) {
      guard testTarget.isTest else { return }
      if knownDependants.contains(testTarget.name) {
        if targetIsConditional {
          conditional.append(testTarget)
        } else {
          known.append(testTarget)
        }
      } else if possibleDependants.contains(testTarget.name) {
        conditional.append(testTarget)
      }
    }

    for testTarget in targets.knownValues {
      inspect(testTarget, conditional: false)
    }
    for testTarget in targets.conditionalValues {
      inspect(testTarget, conditional: true)
    }
    let knownTargets = known.removingDuplicateTargets()
    let knownNames = Set(knownTargets.map(\.name))
    return ManifestList(
      knownValues: knownTargets,
      conditionalValues: conditional.filter {
        !knownNames.contains($0.name)
      }.removingDuplicateTargets(),
      unresolvedValues: unresolved
    )
  }
}

private struct TargetDependencyGraph {
  let unconditional: OrderedDirectedGraph<String>
  let possible: OrderedDirectedGraph<String>

  private let manifestUnresolvedValues: [PackageManifest.UnresolvedValue]
  private let lookup: TargetLookup
  private let targetsByName: [String: PackageManifest.Target]
  private let dependenciesByTargetName: [
    String: ManifestList<PackageManifest.Target>
  ]

  init(
    _ manifest: PackageManifest,
    root: PackageManifest.Target? = nil,
    includingConditionalDependencies: Bool
  ) {
    let lookup = TargetLookup(manifest.targets)
    var candidates = root.map { [$0] } ?? []
    candidates += manifest.targets.possibleValues.filter {
      $0.name != root?.name
    }
    candidates = candidates.removingDuplicateTargets()

    var dependenciesByTargetName: [
      String: ManifestList<PackageManifest.Target>
    ] = [:]
    var unconditionalEdges: [DirectedEdge<String>] = []
    var possibleEdges: [DirectedEdge<String>] = []
    for target in candidates {
      let dependencies = lookup.dependencies(
        of: target,
        includingConditionalDependencies: includingConditionalDependencies,
        includingManifestUnresolvedValues: false
      )
      dependenciesByTargetName[target.name] = dependencies
      unconditionalEdges += dependencies.knownValues.map {
        DirectedEdge(from: target.name, to: $0.name)
      }
      possibleEdges += dependencies.possibleValues.map {
        DirectedEdge(from: target.name, to: $0.name)
      }
    }

    let names = candidates.map(\.name)
    unconditional = OrderedDirectedGraph(
      nodes: names,
      edges: unconditionalEdges
    )
    possible = OrderedDirectedGraph(nodes: names, edges: possibleEdges)
    manifestUnresolvedValues = manifest.targets.unresolvedValues
    self.lookup = lookup
    targetsByName = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.name, $0) }
    )
    self.dependenciesByTargetName = dependenciesByTargetName
  }

  func dependencies(
    of target: PackageManifest.Target,
    transitively: Bool
  ) -> ManifestList<PackageManifest.Target> {
    let knownNames = relatedNames(
      to: target.name,
      direction: .forward,
      transitively: transitively,
      using: unconditional
    )
    let possibleNames = relatedNames(
      to: target.name,
      direction: .forward,
      transitively: transitively,
      using: possible
    )
    let knownNameSet = Set(knownNames)
    return ManifestList(
      knownValues: knownNames.compactMap { targetsByName[$0] },
      conditionalValues: possibleNames.compactMap { name in
        knownNameSet.contains(name) ? nil : targetsByName[name]
      },
      unresolvedValues: unresolvedValues(
        from: [target.name],
        reachableNames: transitively ? possibleNames : []
      )
    )
  }

  func targets(named name: String) -> ManifestList<PackageManifest.Target> {
    lookup.targets(named: name)
  }

  func targets(named names: [String]) -> [PackageManifest.Target] {
    names.compactMap { targetsByName[$0] }
  }

  func orderedClosure(
    from roots: [String],
    using graph: OrderedDirectedGraph<String>
  ) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for root in roots where seen.insert(root).inserted {
      result.append(root)
      var queue = [root]
      var index = 0
      while index < queue.count {
        let current = queue[index]
        index += 1
        for successor in graph.successors(of: current)
          where seen.insert(successor).inserted
        {
          result.append(successor)
          queue.append(successor)
        }
      }
    }
    return result
  }

  func relatedNames(
    to name: String,
    direction: OrderedDirectedGraph<String>.Direction,
    transitively: Bool,
    using graph: OrderedDirectedGraph<String>
  ) -> [String] {
    if transitively {
      return graph.reachable(from: [name], direction: direction)
    }
    return switch direction {
    case .forward: graph.successors(of: name)
    case .reverse: graph.predecessors(of: name)
    }
  }

  func unresolvedValues(
    from roots: [String],
    transitively: Bool
  ) -> [PackageManifest.UnresolvedValue] {
    let reachableNames = transitively
      ? possible.reachable(from: roots)
      : []
    return unresolvedValues(from: roots, reachableNames: reachableNames)
  }

  func unresolvedValues(
    from roots: [String],
    reachableNames: [String]
  ) -> [PackageManifest.UnresolvedValue] {
    var seen: Set<String> = []
    let names = (roots + reachableNames).filter { seen.insert($0).inserted }
    return manifestUnresolvedValues + names.flatMap {
      dependenciesByTargetName[$0]?.unresolvedValues ?? []
    }
  }
}

private struct TargetLookup {
  private let manifestUnresolvedValues: [PackageManifest.UnresolvedValue]
  private let knownTargetsByName: [String: [PackageManifest.Target]]
  private let conditionalTargetsByName: [String: [PackageManifest.Target]]

  init(_ targets: ManifestList<PackageManifest.Target>) {
    manifestUnresolvedValues = targets.unresolvedValues
    knownTargetsByName = Dictionary(grouping: targets.knownValues, by: \.name)
    conditionalTargetsByName = Dictionary(
      grouping: targets.conditionalValues,
      by: \.name
    )
  }

  func targets(named name: String) -> ManifestList<PackageManifest.Target> {
    ManifestList(
      knownValues: knownTargetsByName[name, default: []],
      conditionalValues: conditionalTargetsByName[name, default: []],
      unresolvedValues: manifestUnresolvedValues
    )
  }

  func dependencies(
    of target: PackageManifest.Target,
    includingConditionalDependencies: Bool,
    includingManifestUnresolvedValues: Bool = true
  ) -> ManifestList<PackageManifest.Target> {
    var known: [PackageManifest.Target] = []
    var conditional: [PackageManifest.Target] = []
    var unresolved = (includingManifestUnresolvedValues
      ? manifestUnresolvedValues
      : []) + target.dependencies.unresolvedValues
      + target.dependencies.possibleValues.flatMap(\.unresolvedValues)

    func collect(
      _ dependency: PackageManifest.Target.Dependency,
      conditional declarationIsConditional: Bool
    ) {
      let dependencyIsConditional = declarationIsConditional
        || dependency.condition != nil
      if dependencyIsConditional, !includingConditionalDependencies {
        return
      }

      guard dependency.kind != .product else { return }
      let matches = targets(named: dependency.name)
      if dependency.kind == .byName, matches.possibleValues.count > 1 {
        unresolved.append(
          PackageManifest.UnresolvedValue(
            field: "targets.\(target.name).dependencies",
            expression: "ambiguous by-name dependency \(dependency.name)"
          )
        )
        return
      }
      if matches.possibleValues.isEmpty, dependency.kind == .target {
        unresolved.append(
          PackageManifest.UnresolvedValue(
            field: "targets.\(target.name).dependencies",
            expression: "missing local target \(dependency.name)"
          )
        )
        return
      }

      if dependencyIsConditional {
        conditional.append(contentsOf: matches.possibleValues)
      } else {
        known.append(contentsOf: matches.knownValues)
        conditional.append(contentsOf: matches.conditionalValues)
      }
    }

    for dependency in target.dependencies.knownValues {
      collect(dependency, conditional: false)
    }
    for dependency in target.dependencies.conditionalValues {
      collect(dependency, conditional: true)
    }
    let knownTargets = known.removingDuplicateTargets()
    let knownNames = Set(knownTargets.map(\.name))
    return ManifestList(
      knownValues: knownTargets,
      conditionalValues: conditional.filter {
        !knownNames.contains($0.name)
      }.removingDuplicateTargets(),
      unresolvedValues: unresolved
    )
  }
}

extension [PackageManifest.Target] {
  fileprivate func removingDuplicateTargets() -> Self {
    var names = Set<String>()
    return filter { names.insert($0.name).inserted }
  }
}
