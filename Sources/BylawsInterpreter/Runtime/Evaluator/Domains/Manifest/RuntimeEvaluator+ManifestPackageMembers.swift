import BylawsSemantics

extension RuntimeEvaluator {
  func platformMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Platform
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .minimumVersion: .model(.manifest(.platformVersion(value
          .minimumVersion)))
    default: nil
    }
  }

  func productMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Product
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .kind: .member(productKind(value.kind))
    case .linkage: optionalMember(productLinkage(value.kind)?.rawValue)
    case .targetNames: manifestStrings(value.targetNames)
    case .isComplete: .boolean(value.isComplete)
    default: nil
    }
  }

  func traitMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Trait
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .description: optionalString(value.description)
    case .enabledTraitNames: stringSet(value.enabledTraitNames)
    default: nil
    }
  }

  func dependencyMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Dependency
  ) -> RuntimeValue? {
    switch name {
    case .name: .string(value.name)
    case .sourceKind: .member(dependencySource(value.source).kind)
    case .sourceLocation: .string(dependencySource(value.source).location)
    case .requirement: .model(.manifest(.dependencyRequirement(value
          .requirement)))
    case .traits:
      manifestList(value.traits) {
        .model(.manifest(.dependencyTraitSelection($0)))
      }
    default: nil
    }
  }

  func requirementMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Dependency.Requirement
  ) -> RuntimeValue? {
    switch name {
    case .kind: .member(requirementKind(value))
    case .isExactVersion: .boolean(value.isExactVersion)
    case .minimumVersion:
      optionalModel(value.minimumVersion) { .manifest(.version($0)) }
    case .majorVersion: optionalInteger(value.majorVersion)
    case .lowerBound:
      optionalModel(
        requirementBounds(value).lower,
        { .manifest(.version($0)) }
      )
    case .upperBound:
      optionalModel(
        requirementBounds(value).upper,
        { .manifest(.version($0)) }
      )
    case .branch:
      if case let .branch(branch) = value {
        .optional(.string(branch))
      } else {
        .optional(nil)
      }
    case .revision:
      if case let .revision(revision) = value {
        .optional(.string(revision))
      } else {
        .optional(nil)
      }
    default: nil
    }
  }

  func traitSelectionMember(
    _ name: SupportedAPI.Member,
    _ value: PackageManifest.Dependency.TraitSelection
  ) -> RuntimeValue? {
    switch name {
    case .kind:
      if case .defaults = value.kind { .member(.constant(.defaults)) }
      else { .member(.matcher(.named)) }
    case .name:
      if case let .named(name) = value.kind { .optional(.string(name)) }
      else { .optional(nil) }
    case .condition:
      optionalModel(value.condition) { .manifest(.condition($0)) }
    default: nil
    }
  }

  private func dependencySource(
    _ value: PackageManifest.Dependency.Source
  ) -> (kind: SupportedAPI.MemberLiteral, location: String) {
    switch value {
    case let .url(location): (.constant(.url), location)
    case let .path(location): (.constant(.path), location)
    case let .registryIdentity(location): (
        .constant(.registryIdentity),
        location
      )
    }
  }

  private func productKind(
    _ value: PackageManifest.Product.Kind
  ) -> SupportedAPI.MemberLiteral {
    switch value {
    case .library: .constant(.library)
    case .executable: .constant(.executable)
    case .plugin: .constant(.plugin)
    }
  }

  private func productLinkage(
    _ value: PackageManifest.Product.Kind
  ) -> PackageManifest.Product.LibraryLinkage? {
    guard case let .library(linkage) = value else { return nil }
    return linkage
  }

  private func requirementKind(
    _ value: PackageManifest.Dependency.Requirement
  ) -> SupportedAPI.MemberLiteral {
    switch value {
    case .exact: .constant(.exact)
    case .range: .constant(.range)
    case .closedRange: .constant(.closedRange)
    case .upToNextMajor: .constant(.upToNextMajor)
    case .upToNextMinor: .constant(.upToNextMinor)
    case .branch: .constant(.branch)
    case .revision: .constant(.revision)
    case .local: .constant(.local)
    }
  }

  private func requirementBounds(
    _ value: PackageManifest.Dependency.Requirement
  ) -> (lower: PackageManifest.Version?, upper: PackageManifest.Version?) {
    switch value {
    case let .exact(version): (version, version)
    case let .range(from, upTo): (from, upTo)
    case let .closedRange(from, through): (from, through)
    case let .upToNextMajor(from): (from, nil)
    case let .upToNextMinor(from): (from, nil)
    case .branch, .revision, .local: (nil, nil)
    }
  }
}
