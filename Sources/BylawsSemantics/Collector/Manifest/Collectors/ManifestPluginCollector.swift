import SwiftSyntax

enum ManifestPluginCollector {
  static func usages(
    from expression: ExprSyntax?,
    field: String,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Target.PluginUsage> {
    ManifestListDecoder.list(
      from: expression,
      field: field,
      resolver: resolver,
      nilMeansEmpty: true
    ) { expression in
      if let name = resolver.string(from: expression) {
        return PackageManifest.Target.PluginUsage(name: name)
      }
      guard let call = resolver.call(from: expression),
            call.manifestCallName == .plugin,
            let name = resolver.string(
              from: call.manifestArgument(labelled: "name")
                ?? call.manifestUnlabelledArgument()
            )
      else { return nil }
      let packageExpression = call.manifestArgument(labelled: "package")
      let packageName = resolver.string(from: packageExpression)
      guard packageExpression == nil || packageName != nil else { return nil }
      return PackageManifest.Target.PluginUsage(
        name: name,
        packageName: packageName
      )
    }
  }

  static func capability(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.PluginCapability? {
    guard let expression,
          let call = resolver.call(from: expression)
    else { return nil }
    switch call.manifestCallName {
    case .buildTool: return .buildTool
    case .command:
      guard let intent = intent(
        from: call.manifestArgument(labelled: "intent"),
        resolver: resolver
      ) else { return nil }
      let permissions = ManifestListDecoder.list(
        from: call.manifestArgument(labelled: "permissions"),
        field: "pluginCapability.permissions",
        resolver: resolver
      ) { permission(from: $0, resolver: resolver) }
      guard let resolved = permissions.values else { return nil }
      return .command(intent: intent, permissions: resolved)
    default: return nil
    }
  }

  private static func intent(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.PluginIntent? {
    guard let expression,
          let call = resolver.call(from: expression)
    else { return nil }
    switch call.manifestCallName {
    case .documentationGeneration: return .documentationGeneration
    case .sourceCodeFormatting: return .sourceCodeFormatting
    case .custom:
      guard let verb = resolver.string(
        from: call.manifestArgument(labelled: "verb")
      ), let description = resolver.string(
        from: call.manifestArgument(labelled: "description")
      ) else { return nil }
      return .custom(verb: verb, description: description)
    default: return nil
    }
  }

  private static func permission(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.PluginPermission? {
    guard let call = resolver.call(from: expression),
          let reason = resolver.string(
            from: call.manifestArgument(labelled: "reason")
          )
    else { return nil }
    switch call.manifestCallName {
    case .writeToPackageDirectory:
      return .writeToPackageDirectory(reason: reason)
    case .allowNetworkConnections:
      guard let scope = networkScope(
        from: call.manifestArgument(labelled: "scope"),
        resolver: resolver
      ) else { return nil }
      return .allowNetworkConnections(scope: scope, reason: reason)
    default: return nil
    }
  }

  private static func networkScope(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.NetworkScope? {
    if let name = resolver.memberName(from: expression) {
      return switch name {
      case "none": PackageManifest.Target.NetworkScope.none
      case "docker": .docker
      case "unixDomainSocket": .unixDomainSocket
      default: nil
      }
    }
    guard let expression,
          let call = resolver.call(from: expression)
    else { return nil }
    let ports = networkPorts(
      from: call.manifestArgument(labelled: "ports")
        ?? call.manifestUnlabelledArgument(),
      resolver: resolver
    )
    guard let ports else { return nil }
    return switch call.manifestCallName {
    case .local: .local(ports: ports)
    case .all: .all(ports: ports)
    default: nil
    }
  }

  private static func networkPorts(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Target.NetworkPorts? {
    guard let expression else { return .values([]) }
    if let range = integerRange(from: expression, resolver: resolver) {
      return .range(from: range.lowerBound, upTo: range.upperBound)
    }
    let values = resolver.array(from: expression)
    guard values.unresolved.isEmpty else { return nil }
    var integers: [Int] = []
    for value in values.known {
      guard let integer = resolver.integer(from: value) else { return nil }
      integers.append(integer)
    }
    return .values(integers)
  }

  private static func integerRange(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> (lowerBound: Int, upperBound: Int)? {
    guard let expression = resolver.resolvedExpression(from: expression) else {
      return nil
    }
    guard let operands = ManifestBinaryOperation(expression)?
      .operands(forOperator: ["..<"]),
      let lowerBound = resolver.integer(from: operands.left),
      let upperBound = resolver.integer(from: operands.right)
    else { return nil }
    return (lowerBound, upperBound)
  }
}
