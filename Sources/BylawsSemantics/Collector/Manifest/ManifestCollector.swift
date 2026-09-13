import Foundation
import SwiftParser
import SwiftSyntax

enum ManifestCollector {
  static func manifest(in source: String) -> PackageManifest {
    let tree = Parser.parse(source: source)
    let resolver = ManifestSyntaxResolver(tree: tree, source: source)
    guard let call = packageCall(in: tree) else {
      let issue = PackageManifest.UnresolvedValue(
        field: "package",
        expression: "Package initialiser"
      )
      return PackageManifest(
        targets: ManifestList(unresolvedValues: [issue]),
        unresolvedValues: [issue]
      )
    }

    var fields = ManifestFields(call: call, resolver: resolver)
    let mutationFinder = ManifestMutationFinder(after: call)
    mutationFinder.walk(tree)
    ManifestMutationApplier.apply(
      mutationFinder.mutations,
      to: &fields,
      resolver: resolver
    )

    let syntaxIssues = tree.hasError
      ? [
        PackageManifest.UnresolvedValue(
          field: "package",
          expression: "manifest contains syntax errors"
        ),
      ]
      : []
    return fields.manifest(
      toolsVersion: toolsVersion(in: source),
      syntaxIssues: syntaxIssues
    )
  }

  private static func packageCall(in tree: SourceFileSyntax)
    -> FunctionCallExprSyntax?
  {
    for statement in tree.statements {
      guard let declaration = statement.item.as(VariableDeclSyntax.self),
            declaration.bindingSpecifier.text == "let"
      else { continue }
      for binding in declaration.bindings {
        guard binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
          == "package",
          let call = binding.initializer?.value
          .as(FunctionCallExprSyntax.self),
          call.isManifestPackageInitializer
        else { continue }
        return call
      }
    }
    return nil
  }

  private static func toolsVersion(in source: String)
    -> PackageManifest.ToolsVersion?
  {
    guard let line = source.split(
      separator: "\n",
      omittingEmptySubsequences: false
    )
    .first(where: { $0.contains("swift-tools-version:") }),
    let separator = line.range(of: "swift-tools-version:")
    else { return nil }
    let written = line[separator.upperBound...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return PackageManifest.ToolsVersion(written)
  }
}

func memberName(from expression: ExprSyntax?) -> String? {
  guard let expression else { return nil }
  if let member = expression.as(MemberAccessExprSyntax.self) {
    return member.declName.baseName.text
  }
  return nil
}
