import SwiftSyntax

enum ManifestPlatformCollector {
  static func platforms(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Platform> {
    ManifestListDecoder.list(
      from: expression,
      field: "platforms",
      resolver: resolver,
      nilMeansEmpty: true
    ) {
      platform(from: $0, resolver: resolver)
    }
  }

  static func platform(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Platform? {
    guard let call = resolver.call(from: expression),
          let form = memberName(from: call.calledExpression)
    else { return nil }
    let supportedPlatforms = [
      "android",
      "driverKit",
      "iOS",
      "linux",
      "macCatalyst",
      "macOS",
      "openbsd",
      "tvOS",
      "visionOS",
      "wasi",
      "watchOS",
      "windows",
    ]
    guard form == "custom" || supportedPlatforms.contains(form) else {
      return nil
    }
    let name: String
    let versionExpression: ExprSyntax?
    if form == "custom" {
      guard let customName = resolver.string(
        from: call.manifestUnlabelledArgument()
      ) else { return nil }
      name = customName
      versionExpression = call.manifestArgument(labelled: "versionString")
        ?? call.manifestUnlabelledArgument(at: 1)
    } else {
      name = form
      versionExpression = call.manifestUnlabelledArgument()
    }
    guard let versionExpression,
          let writtenVersion = resolver.string(from: versionExpression)
          ?? resolver.memberName(from: versionExpression)?.droppingLeadingV,
          let version = PackageManifest.PlatformVersion(writtenVersion)
    else { return nil }
    return PackageManifest.Platform(name: name, minimumVersion: version)
  }
}

extension String {
  fileprivate var droppingLeadingV: String {
    let version = hasPrefix("v") ? String(dropFirst()) : self
    return version.replacing("_", with: ".")
  }
}
