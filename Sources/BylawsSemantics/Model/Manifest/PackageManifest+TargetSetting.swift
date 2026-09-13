extension PackageManifest.Target {
  /// A compiler or linker setting declared by a target.
  public struct Setting: Sendable, Hashable, Codable {
    /// The tool that receives the setting.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Tool: String, CaseIterable, Sendable, Hashable, Codable {
      /// The Swift compiler.
      case swift

      /// The C compiler.
      case c

      /// The C++ compiler.
      case cxx

      /// The linker.
      case linker
    }

    /// The operation that the setting applies.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum Value: Sendable, Hashable, Codable {
      /// Defines a compilation condition or preprocessor value.
      case define(name: String, value: String?)

      /// Passes arguments directly to the tool.
      case unsafeFlags([String])

      /// Adds a C or C++ header search path.
      case headerSearchPath(String)

      /// Enables an upcoming Swift feature.
      case enableUpcomingFeature(String)

      /// Enables an experimental Swift feature.
      case enableExperimentalFeature(String)

      /// Enables strict memory-safety checking.
      case strictMemorySafety

      /// Selects the Swift interoperability mode.
      case interoperabilityMode(String)

      /// Selects the Swift language mode.
      case swiftLanguageMode(String)

      /// Sets the diagnostic level for every warning.
      case treatAllWarnings(as: WarningLevel)

      /// Sets the diagnostic level for one warning.
      case treatWarning(String, as: WarningLevel)

      /// Enables one warning.
      case enableWarning(String)

      /// Disables one warning.
      case disableWarning(String)

      /// Sets the module's default actor isolation.
      case defaultIsolation(DefaultIsolation?)

      /// Links a system library.
      case linkedLibrary(String)

      /// Links a system framework.
      case linkedFramework(String)
    }

    /// A warning's diagnostic level.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum WarningLevel: String, CaseIterable, Sendable, Hashable,
      Codable
    {
      /// Reports the diagnostic as a warning.
      case warning

      /// Reports the diagnostic as an error.
      case error
    }

    /// A module's default actor isolation.
    ///
    /// Later versions may add cases.
    @nonexhaustive
    public enum DefaultIsolation: String, CaseIterable, Sendable, Hashable,
      Codable
    {
      /// Global main-actor isolation.
      case mainActor
    }

    /// The tool that receives the setting.
    public let tool: Tool

    /// The operation that the setting applies.
    public let value: Value

    /// The condition that controls the setting.
    public let condition: PackageManifest.Condition?

    /// Creates a target-setting record.
    public init?(
      tool: Tool,
      value: Value,
      condition: PackageManifest.Condition? = nil
    ) {
      guard Self.supports(value, for: tool) else { return nil }
      self.tool = tool
      self.value = value
      self.condition = condition
    }

    /// Decodes and validates a target setting.
    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let tool = try container.decode(Tool.self, forKey: .tool)
      let value = try container.decode(Value.self, forKey: .value)
      let condition = try container.decodeIfPresent(
        PackageManifest.Condition.self,
        forKey: .condition
      )
      guard let setting = Self(
        tool: tool,
        value: value,
        condition: condition
      ) else {
        throw DecodingError.dataCorruptedError(
          forKey: .value,
          in: container,
          debugDescription: "The build setting is not valid for this tool."
        )
      }
      self = setting
    }

    /// Whether the setting passes unchecked arguments to a tool.
    public var usesUnsafeFlags: Bool {
      if case .unsafeFlags = value { return true }
      return false
    }

    private static func supports(_ value: Value, for tool: Tool) -> Bool {
      switch value {
      case let .define(name: _, value: value):
        tool == .c || tool == .cxx || (tool == .swift && value == nil)
      case .unsafeFlags:
        true
      case .headerSearchPath:
        tool == .c || tool == .cxx
      case .enableUpcomingFeature,
           .enableExperimentalFeature,
           .strictMemorySafety,
           .interoperabilityMode,
           .swiftLanguageMode,
           .defaultIsolation:
        tool == .swift
      case .treatAllWarnings, .treatWarning:
        tool != .linker
      case .enableWarning, .disableWarning:
        tool == .c || tool == .cxx
      case .linkedLibrary, .linkedFramework:
        tool == .linker
      }
    }

    private enum CodingKeys: String, CodingKey {
      case condition
      case tool
      case value
    }
  }
}
