extension PackageManifest {
  /// A semantic version used by a package dependency requirement.
  public struct Version: Sendable, Hashable, Codable, Comparable,
    LosslessStringConvertible
  {
    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int

    /// The identifiers that follow the version's hyphen.
    public let prereleaseIdentifiers: [String]

    /// The identifiers that follow the version's plus sign.
    public let buildMetadataIdentifiers: [String]

    /// Creates a semantic version from its components.
    public init(
      _ major: Int,
      _ minor: Int,
      _ patch: Int,
      prereleaseIdentifiers: [String] = [],
      buildMetadataIdentifiers: [String] = []
    ) {
      precondition(major >= 0 && minor >= 0 && patch >= 0)
      precondition(
        Self.validIdentifiers(prereleaseIdentifiers, allowLeadingZero: false)
      )
      precondition(
        Self.validIdentifiers(buildMetadataIdentifiers, allowLeadingZero: true)
      )
      self.major = major
      self.minor = minor
      self.patch = patch
      self.prereleaseIdentifiers = prereleaseIdentifiers
      self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }

    /// Creates a semantic version from its text representation.
    public init?(_ description: String) {
      let buildParts = description.split(
        separator: "+",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      let buildMetadataIdentifiers = buildParts.count == 2
        ? buildParts[1].split(
          separator: ".",
          omittingEmptySubsequences: false
        ).map(String.init)
        : []

      let prereleaseParts = buildParts[0].split(
        separator: "-",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )
      let prereleaseIdentifiers = prereleaseParts.count == 2
        ? prereleaseParts[1].split(
          separator: ".",
          omittingEmptySubsequences: false
        ).map(String.init)
        : []

      let components = prereleaseParts[0].split(
        separator: ".",
        omittingEmptySubsequences: false
      )
      guard components.count == 3,
            components.allSatisfy(Self.validNumericIdentifier),
            Self.validIdentifiers(
              prereleaseIdentifiers,
              allowLeadingZero: false
            ),
            Self.validIdentifiers(
              buildMetadataIdentifiers,
              allowLeadingZero: true
            ),
            let major = Int(components[0]),
            let minor = Int(components[1]),
            let patch = Int(components[2])
      else { return nil }

      self.major = major
      self.minor = minor
      self.patch = patch
      self.prereleaseIdentifiers = prereleaseIdentifiers
      self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }

    /// The semantic version as text.
    public var description: String {
      var result = "\(major).\(minor).\(patch)"
      if !prereleaseIdentifiers.isEmpty {
        result += "-\(prereleaseIdentifiers.joined(separator: "."))"
      }
      if !buildMetadataIdentifiers.isEmpty {
        result += "+\(buildMetadataIdentifiers.joined(separator: "."))"
      }
      return result
    }

    /// Returns whether two versions have the same precedence.
    public static func == (lhs: Version, rhs: Version) -> Bool {
      lhs.major == rhs.major
        && lhs.minor == rhs.minor
        && lhs.patch == rhs.patch
        && lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers
    }

    /// Hashes the parts of the version that determine its precedence.
    public func hash(into hasher: inout Hasher) {
      hasher.combine(major)
      hasher.combine(minor)
      hasher.combine(patch)
      hasher.combine(prereleaseIdentifiers)
    }

    /// Returns whether `lhs` has lower semantic-version precedence than `rhs`.
    public static func < (lhs: Version, rhs: Version) -> Bool {
      if lhs.major != rhs.major { return lhs.major < rhs.major }
      if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
      if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
      return prereleasePrecedes(
        lhs.prereleaseIdentifiers,
        rhs.prereleaseIdentifiers
      )
    }

    private static func prereleasePrecedes(
      _ lhs: [String],
      _ rhs: [String]
    ) -> Bool {
      if lhs.isEmpty { return false }
      if rhs.isEmpty { return true }
      for (left, right) in zip(lhs, rhs) where left != right {
        switch (Int(left), Int(right)) {
        case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return left < right
        }
      }
      return lhs.count < rhs.count
    }

    private static func validIdentifiers(
      _ identifiers: [String],
      allowLeadingZero: Bool
    ) -> Bool {
      identifiers.allSatisfy { identifier in
        guard !identifier.isEmpty,
              identifier.utf8.allSatisfy({ byte in
                byte == 45
                  || (48...57).contains(byte)
                  || (65...90).contains(byte)
                  || (97...122).contains(byte)
              })
        else { return false }
        return allowLeadingZero
          || !identifier.allSatisfy(\.isNumber)
          || validNumericIdentifier(Substring(identifier))
      }
    }

    private static func validNumericIdentifier(_ identifier: Substring)
      -> Bool
    {
      !identifier.isEmpty
        && identifier.allSatisfy(\.isNumber)
        && (identifier.count == 1 || identifier.first != "0")
    }
  }
}
