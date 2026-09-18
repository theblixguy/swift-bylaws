import BylawsPaths
import BylawsSyntax

enum ManifestDependencyCollector {
  static func dependencies(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Dependency> {
    ManifestListDecoder.list(
      from: expression,
      field: "dependencies",
      resolver: resolver
    ) {
      dependency(from: $0, resolver: resolver)
    }
  }

  static func dependency(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Dependency? {
    guard let call = resolver.call(from: expression),
          call.manifestCallName == .package,
          let source = source(from: call, resolver: resolver),
          let requirement = requirement(
            from: call,
            source: source,
            resolver: resolver
          )
    else { return nil }
    let nameExpression = call.manifestArgument(labelled: "name")
    let resolvedName = resolver.string(from: nameExpression)
    guard nameExpression == nil || resolvedName != nil else { return nil }
    let name = resolvedName ?? source.inferredName
    guard !name.isEmpty else { return nil }
    return PackageManifest.Dependency(
      name: name,
      source: source,
      requirement: requirement,
      traits: traits(
        from: call.manifestArgument(labelled: "traits"),
        resolver: resolver
      )
    )
  }

  private static func source(
    from call: FunctionCallExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Dependency.Source? {
    if let value = resolver.string(
      from: call.manifestArgument(labelled: "url")
    ) { return .url(value) }
    if let value = resolver.string(
      from: call.manifestArgument(labelled: "path")
    ) { return .path(value) }
    if let value = resolver
      .string(from: call.manifestArgument(labelled: "id"))
    {
      return .registryIdentity(value)
    }
    return nil
  }

  private static func requirement(
    from call: FunctionCallExprSyntax,
    source: PackageManifest.Dependency.Source,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Dependency.Requirement? {
    if case .path = source { return .local }
    let labelled: [(
      String,
      (PackageManifest.Version) -> PackageManifest.Dependency.Requirement
    )] = [
      ("exact", { .exact($0) }),
      ("from", { .upToNextMajor(from: $0) }),
    ]
    for (label, make) in labelled {
      if let written = resolver
        .string(from: call.manifestArgument(labelled: label)),
        let version = PackageManifest.Version(written)
      { return make(version) }
    }
    if let branch = resolver.string(
      from: call.manifestArgument(labelled: "branch")
    ) { return .branch(branch) }
    if let revision = resolver.string(
      from: call.manifestArgument(labelled: "revision")
    ) { return .revision(revision) }
    guard let expression = call.manifestUnlabelledArgument() else { return nil }
    if let range = versionRange(from: expression, resolver: resolver) {
      return range.isClosed
        ? .closedRange(from: range.lowerBound, through: range.upperBound)
        : .range(from: range.lowerBound, upTo: range.upperBound)
    }
    guard let requirement = resolver.call(from: expression),
          let written = resolver.string(
            from: requirement.manifestArgument(labelled: "from")
              ?? requirement.manifestUnlabelledArgument()
          ),
          let version = PackageManifest.Version(written)
    else { return nil }
    return switch requirement.manifestCallName {
    case .upToNextMajor: .upToNextMajor(from: version)
    case .upToNextMinor: .upToNextMinor(from: version)
    case .exact: .exact(version)
    default: nil
    }
  }

  private static func traits(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Dependency.TraitSelection> {
    guard let expression else {
      return ManifestList(knownValues: [.defaults])
    }
    return ManifestListDecoder.list(
      from: expression,
      field: "dependency.traits",
      resolver: resolver
    ) { expression in
      if let name = resolver.string(from: expression) {
        return .init(kind: .named(name))
      }
      if resolver
        .memberName(from: expression) == "defaults" { return .defaults }
      guard let call = resolver.call(from: expression),
            call.manifestCallName == .trait,
            let name = resolver.string(
              from: call.manifestArgument(labelled: "name")
                ?? call.manifestUnlabelledArgument()
            )
      else { return nil }
      let conditionExpression = call.manifestArgument(labelled: "condition")
      let parsedCondition = ManifestTargetCollector.condition(
        from: conditionExpression,
        resolver: resolver
      )
      guard conditionExpression == nil || parsedCondition != nil else {
        return nil
      }
      return .init(
        kind: .named(name),
        condition: parsedCondition
      )
    }
  }

  private static func versionRange(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> (
    lowerBound: PackageManifest.Version,
    upperBound: PackageManifest.Version,
    isClosed: Bool
  )? {
    guard let expression = resolver.resolvedExpression(from: expression) else {
      return nil
    }
    guard let range = ManifestBinaryOperation(expression),
          let operands = range.operands(forOperator: ["..<", "..."]),
          let lower = resolver.string(from: operands.left),
          let upper = resolver.string(from: operands.right),
          let lowerVersion = PackageManifest.Version(lower),
          let upperVersion = PackageManifest.Version(upper)
    else { return nil }
    return (lowerVersion, upperVersion, range.writtenOperator == "...")
  }
}

extension PackageManifest.Dependency.Source {
  fileprivate var inferredName: String {
    let location = switch self {
    case let .url(url), let .path(url): url
    case let .registryIdentity(identity): identity
    }
    let lastComponent = LexicalFilePath(location).lastComponent ?? location
    return lastComponent.hasSuffix(".git")
      ? String(lastComponent.dropLast(4))
      : lastComponent
  }
}
