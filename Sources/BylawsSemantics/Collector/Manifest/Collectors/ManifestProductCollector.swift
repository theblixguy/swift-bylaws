import SwiftSyntax

enum ManifestProductCollector {
  static func products(
    from expression: ExprSyntax?,
    resolver: ManifestSyntaxResolver
  ) -> ManifestList<PackageManifest.Product> {
    ManifestListDecoder.list(
      from: expression,
      field: "products",
      resolver: resolver
    ) {
      product(from: $0, resolver: resolver)
    }
  }

  static func product(
    from expression: ExprSyntax,
    resolver: ManifestSyntaxResolver
  ) -> PackageManifest.Product? {
    guard let call = resolver.call(from: expression),
          let name = resolver.string(
            from: call.manifestArgument(labelled: "name")
          ),
          let targetExpression = call.manifestArgument(labelled: "targets")
    else { return nil }
    let targets = resolver.strings(from: targetExpression)
    let kind: PackageManifest.Product.Kind
    switch call.manifestCallName {
    case .library:
      let typeExpression = call.manifestArgument(labelled: "type")
      let writtenType = resolver.memberName(from: typeExpression)
      guard typeExpression == nil
        || ["static", "dynamic"].contains(writtenType)
      else { return nil }
      let linkage = switch writtenType {
      case "static": PackageManifest.Product.LibraryLinkage.static
      case "dynamic": PackageManifest.Product.LibraryLinkage.dynamic
      default: PackageManifest.Product.LibraryLinkage.automatic
      }
      kind = .library(linkage: linkage)
    case .executable: kind = .executable
    case .plugin: kind = .plugin
    default: return nil
    }
    return PackageManifest.Product(
      name: name,
      kind: kind,
      targetNames: targets.assigningField("products.\(name).targetNames")
    )
  }
}
