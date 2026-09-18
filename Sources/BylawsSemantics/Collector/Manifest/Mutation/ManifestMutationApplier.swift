import BylawsSyntax

enum ManifestMutationApplier {
  static func apply(
    _ mutations: [ManifestMutation],
    to fields: inout ManifestFields,
    resolver: ManifestSyntaxResolver
  ) {
    for mutation in mutations {
      apply(mutation, to: &fields, resolver: resolver)
    }
  }

  private static func apply(
    _ mutation: ManifestMutation,
    to fields: inout ManifestFields,
    resolver: ManifestSyntaxResolver
  ) {
    switch mutation.field {
    case .dependencies:
      applyList(mutation, to: &fields, \.dependencies, resolver: resolver) {
        ManifestDependencyCollector.dependency(from: $0, resolver: resolver)
      }
    case .products:
      applyList(mutation, to: &fields, \.products, resolver: resolver) {
        ManifestProductCollector.product(from: $0, resolver: resolver)
      }
    case .platforms:
      applyList(
        mutation,
        to: &fields,
        \.platforms,
        resolver: resolver,
        nilMeansEmpty: true
      ) { ManifestPlatformCollector.platform(from: $0, resolver: resolver) }
    case .swiftLanguageModes, .swiftLanguageVersions:
      applyList(
        mutation,
        to: &fields,
        \.swiftLanguageModes,
        resolver: resolver,
        nilMeansEmpty: true
      ) { ManifestListDecoder.memberName(from: $0, resolver: resolver) }
    case .targets:
      applyList(mutation, to: &fields, \.targets, resolver: resolver) {
        ManifestTargetCollector.target(from: $0, resolver: resolver)
      }
    case .traits:
      guard mutation.conditionHolds != false else { return }
      let issue = resolver.issue(field: "traits", expression: mutation.syntax)
      fields.traits = ManifestTraitLists(
        declarations: fields.traits.declarations.adding([issue]),
        defaults: fields.traits.defaults.adding([
          PackageManifest.UnresolvedValue(
            field: "defaultTraitNames",
            expression: issue.expression,
            line: issue.line,
            column: issue.column
          ),
        ])
      )
    case .name:
      applyScalar(mutation, to: &fields, \.name, resolver: resolver) {
        resolver.string(from: $0)
      }
    case .defaultLocalization:
      applyScalar(
        mutation,
        to: &fields,
        \.defaultLocalization,
        resolver: resolver
      ) { resolver.string(from: $0) }
    case .cLanguageStandard:
      applyScalar(
        mutation,
        to: &fields,
        \.cLanguageStandard,
        resolver: resolver
      ) {
        resolver.memberName(from: $0)
      }
    case .cxxLanguageStandard:
      applyScalar(
        mutation,
        to: &fields,
        \.cxxLanguageStandard,
        resolver: resolver
      ) {
        resolver.memberName(from: $0)
      }
    }
  }

  private static func applyList<Element: Sendable & Hashable & Codable>(
    _ mutation: ManifestMutation,
    to fields: inout ManifestFields,
    _ keyPath: WritableKeyPath<ManifestFields, ManifestList<Element>>,
    resolver: ManifestSyntaxResolver,
    nilMeansEmpty: Bool = false,
    decode: (ExprSyntax) -> Element?
  ) {
    fields[keyPath: keyPath] = ManifestListDecoder.applying(
      mutation,
      to: fields[keyPath: keyPath],
      resolver: resolver,
      nilMeansEmpty: nilMeansEmpty,
      decode: decode
    )
  }

  private static func applyScalar<Value>(
    _ mutation: ManifestMutation,
    to fields: inout ManifestFields,
    _ keyPath: WritableKeyPath<ManifestFields, Value?>,
    resolver: ManifestSyntaxResolver,
    decode: (ExprSyntax) -> Value?
  ) {
    let result = ManifestListDecoder.scalarMutation(
      mutation,
      current: fields[keyPath: keyPath],
      resolver: resolver,
      decode: decode
    )
    fields[keyPath: keyPath] = result.value
    fields.unresolved.append(contentsOf: result.issues)
  }
}
