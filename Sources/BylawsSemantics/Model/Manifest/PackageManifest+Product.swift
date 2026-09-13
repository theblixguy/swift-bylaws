extension PackageManifest {
  /// One product declared in a `Package.swift` file.
  public struct Product: Sendable, Hashable, Codable {
    /// A SwiftPM product declaration form.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Kind: Sendable, Hashable, Codable {
      /// A library product.
      case library(linkage: LibraryLinkage)

      /// An executable.
      case executable

      /// A package plugin.
      case plugin
    }

    /// How a library product is linked.
    public enum LibraryLinkage: String, CaseIterable, Sendable, Hashable,
      Codable
    {
      /// SwiftPM selects the linkage.
      case automatic

      /// Static linkage.
      case `static`

      /// Dynamic linkage.
      case dynamic
    }

    /// The product name.
    public let name: String

    /// The product declaration form.
    public let kind: Kind

    /// The targets that the product contains.
    public let targetNames: ManifestList<String>

    /// Whether every product field was resolved.
    public var isComplete: Bool { targetNames.isComplete }

    /// Creates a product record.
    public init(
      name: String,
      kind: Kind,
      targetNames: ManifestList<String>
    ) {
      self.name = name
      self.kind = kind
      self.targetNames = targetNames
    }

    /// Creates a product from resolved target names.
    public init(name: String, kind: Kind, targetNames: [String]) {
      self.init(
        name: name,
        kind: kind,
        targetNames: ManifestList(knownValues: targetNames)
      )
    }
  }
}
