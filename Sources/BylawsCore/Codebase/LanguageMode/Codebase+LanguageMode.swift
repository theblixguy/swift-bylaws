extension Codebase {
  /// The language mode to use, or the project settings to read before parsing.
  public enum LanguageMode: Sendable, Hashable {
    /// Reads the selected project settings, with Swift 6 as the fallback.
    ///
    /// When both project types are selected, SwiftPM settings take precedence
    /// for package files. Settings that cannot be resolved fail the query.
    case automatic(Projects)

    /// Uses Swift 4 syntax without reading project settings.
    case v4

    /// Uses Swift 5 syntax without reading project settings.
    case v5

    /// Uses Swift 6 syntax without reading project settings.
    case v6

    /// The project types that supply language settings.
    public struct Projects: OptionSet, Sendable, Hashable {
      /// The bits that identify the selected project types.
      public let rawValue: UInt8

      /// Creates a selection from its raw bits.
      public init(rawValue: UInt8) {
        self.rawValue = rawValue
      }

      /// Reads each file's nearest SwiftPM manifest within the codebase root.
      public static let swiftPM = Self(rawValue: 1 << 0)

      /// Reads the Xcode projects directly inside the codebase root.
      public static let xcode = Self(rawValue: 1 << 1)
    }
  }
}
