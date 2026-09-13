extension PackageManifest {
  /// The Swift tools version declared by a manifest.
  public struct ToolsVersion: Sendable, Hashable, Codable, Comparable,
    CustomStringConvertible
  {
    /// The numeric components in declaration order.
    public let components: [Int]

    /// The written version.
    public let description: String

    /// Creates a tools version from its written form, such as `6.2`.
    ///
    /// Returns `nil` when `description` is not dot-separated decimals.
    public init?(_ description: String) {
      guard let components = Self.components(in: description) else {
        return nil
      }
      self.components = components
      self.description = description
    }

    /// Creates a tools version from numeric components.
    public init(_ major: Int, _ rest: Int...) {
      components = [major] + rest
      description = components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
      compare(lhs.components, rhs.components)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
      normalised(lhs.components) == normalised(rhs.components)
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(normalised(components))
    }

    fileprivate static func components(in description: String) -> [Int]? {
      let parts = description.split(
        separator: ".",
        omittingEmptySubsequences: false
      )
      guard !parts.isEmpty,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
      else { return nil }
      let components = parts.compactMap { Int($0) }
      guard components.count == parts.count else { return nil }
      return components
    }
  }

  /// A deployment platform version.
  public struct PlatformVersion: Sendable, Hashable, Codable, Comparable,
    CustomStringConvertible
  {
    /// The numeric components in declaration order.
    public let components: [Int]

    /// The written version.
    public let description: String

    /// Creates a platform version from its written form, such as `10.15`.
    ///
    /// Returns `nil` when `description` is not dot-separated decimals.
    public init?(_ description: String) {
      guard let components = ToolsVersion.components(in: description) else {
        return nil
      }
      self.components = components
      self.description = description
    }

    /// Creates a platform version from numeric components.
    public init(_ major: Int, _ rest: Int...) {
      components = [major] + rest
      description = components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
      compare(lhs.components, rhs.components)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
      normalised(lhs.components) == normalised(rhs.components)
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(normalised(components))
    }
  }
}

private func compare(_ lhs: [Int], _ rhs: [Int]) -> Bool {
  let count = max(lhs.count, rhs.count)
  for index in 0..<count {
    let left = index < lhs.count ? lhs[index] : 0
    let right = index < rhs.count ? rhs[index] : 0
    if left != right { return left < right }
  }
  return false
}

private func normalised(_ components: [Int]) -> [Int] {
  var components = components
  while components.count > 1, components.last == 0 {
    components.removeLast()
  }
  return components
}
