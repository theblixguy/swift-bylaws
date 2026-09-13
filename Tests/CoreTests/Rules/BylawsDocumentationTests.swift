import Bylaws
import Testing

@Suite("Public API documentation", .codebase(.bylaws), .tags(.layering))
struct BylawsDocumentationTests {
  @Test("Public declarations have documentation", .tags(.architecture))
  func publicDeclarations() async throws {
    func undocumented<D: Sendable & Documented & Visible>(
      _ selection: Selection<D>,
      excluding inheritedDocumentation: (D) -> Bool = { _ in false }
    ) -> Violations<D> {
      let publicDeclarations = selection.where(.isPublic)
        .filter { !inheritedDocumentation($0) }
      return Violations(
        rule: "have a documentation comment",
        offenders: publicDeclarations.filter { !$0.isDocumented },
        checkedCount: publicDeclarations.count
      )
    }

    #expect(try await undocumented(Codebase.bylaws.types).isEmpty)
    let functions = try await undocumented(
      Codebase.bylaws.functions,
      excluding: Self.inheritsFunctionDocumentation
    )
    let properties = try await undocumented(
      Codebase.bylaws.properties,
      excluding: Self.inheritsPropertyDocumentation
    )
    let initializers = try await undocumented(
      Codebase.bylaws.initializers,
      excluding: Self.inheritsInitializerDocumentation
    )
    #expect(functions.isEmpty, "\(functions)")
    #expect(properties.isEmpty, "\(properties)")
    #expect(initializers.isEmpty, "\(initializers)")
    #expect(try await undocumented(Codebase.bylaws.typealiases).isEmpty)

    let publicEnumCases = try await Codebase.bylaws.enums
      .where(.isPublic)
      .flatMap(\.cases)
    for enumCase in publicEnumCases {
      #expect(enumCase.isDocumented, sourceLocation: enumCase.testingLocation)
    }
  }

  private static let inheritedFunctionDocumentation: [FunctionWitness] = [
    .init(
      fileName: "AdvisoryTrait.swift",
      enclosingTypeName: "AdvisoryTrait",
      name: "provideScope",
      labels: ["for", "testCase", "performing"]
    ),
    .init(
      fileName: "AnnotatesViolationsTrait.swift",
      enclosingTypeName: "AnnotatesViolationsTrait",
      name: "provideScope",
      labels: ["for", "testCase", "performing"]
    ),
    .init(
      fileName: "BaselineTrait.swift",
      enclosingTypeName: "BaselineTrait",
      name: "provideScope",
      labels: ["for", "testCase", "performing"]
    ),
    .init(
      fileName: "CodebaseTrait.swift",
      enclosingTypeName: "CodebaseTrait",
      name: "prepare",
      labels: ["for"]
    ),
    .init(
      fileName: "CodebaseTrait.swift",
      enclosingTypeName: "CodebaseTrait",
      name: "provideScope",
      labels: ["for", "testCase", "performing"]
    ),
    .init(
      fileName: "Baseline.swift",
      enclosingTypeName: "Baseline.Entry",
      name: "<",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "Codebase.swift",
      enclosingTypeName: "Codebase.Root",
      name: "==",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "Codebase.swift",
      enclosingTypeName: "Codebase.Root",
      name: "hash",
      labels: ["into"]
    ),
    .init(
      fileName: "Glob.swift",
      enclosingTypeName: "Glob",
      name: "==",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "Glob.swift",
      enclosingTypeName: "Glob",
      name: "hash",
      labels: ["into"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.ToolsVersion",
      name: "<",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.ToolsVersion",
      name: "==",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.ToolsVersion",
      name: "hash",
      labels: ["into"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.PlatformVersion",
      name: "<",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.PlatformVersion",
      name: "==",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "PackageManifest+NumericVersion.swift",
      enclosingTypeName: "PackageManifest.PlatformVersion",
      name: "hash",
      labels: ["into"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "Rule.ID",
      name: "encode",
      labels: ["to"]
    ),
    .init(
      fileName: "Violations.swift",
      enclosingTypeName: "Violations",
      name: "==",
      labels: ["lhs", "rhs"]
    ),
    .init(
      fileName: "Violations.swift",
      enclosingTypeName: "Violations",
      name: "hash",
      labels: ["into"]
    ),
    .init(
      fileName: "Violations.swift",
      enclosingTypeName: "Violations",
      name: "encode",
      labels: ["to"]
    ),
  ] + [
    "Actor", "Class", "Enum", "EnumCase", "Extension", "Function",
    "FunctionCall", "Import", "Initializer", "Property",
    "ProtocolDeclaration", "SourceFile", "Struct", "Typealias",
  ].map {
    FunctionWitness(
      fileName: "TestConformances.swift",
      enclosingTypeName: $0,
      name: "encodeTestArgument",
      labels: ["to"]
    )
  }

  private static let modelPropertyNames: Set<String> = [
    "allInheritedTypes", "attributes", "documentation", "enclosingTypeName",
    "extensionInheritedTypes", "functions", "inheritedTypes", "initializers",
    "location", "name", "properties", "visibility",
  ]

  private static let nominalTypeStorageNames: Set<String> = [
    "allInheritedTypes", "attributes", "documentation", "enclosingTypeName",
    "extensionInheritedTypes", "genericParameters", "inheritedTypes",
    "isNonisolated", "location", "name", "sourceRange", "visibility",
  ]

  private static let inheritedPropertyDocumentation: [PropertyWitnessGroup] = [
    .init(
      fileName: "CodebaseError.swift",
      enclosingTypeName: "CodebaseError",
      names: ["description"]
    ),
    .init(
      fileName: "ImportGraph.swift",
      enclosingTypeName: "ImportGraph.Target",
      names: ["description"]
    ),
    .init(
      fileName: "Matcher.swift",
      enclosingTypeName: "Matcher",
      names: ["description"]
    ),
    .init(
      fileName: "Selection.swift",
      enclosingTypeName: "Selection",
      names: ["description", "endIndex", "startIndex"]
    ),
    .init(
      fileName: "Violations.swift",
      enclosingTypeName: "Violations",
      names: ["description"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "Rule.ID",
      names: ["description"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "Rule",
      names: ["description"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "RuleError",
      names: ["description"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "RuleError.Cause",
      names: ["description"]
    ),
    .init(
      fileName: "IndexSymbol.swift",
      enclosingTypeName: "IndexSymbol",
      names: ["description"]
    ),
    .init(
      fileName: "SymbolRole.swift",
      enclosingTypeName: "SymbolRole",
      names: ["rawValue"]
    ),
    .init(
      fileName: "Diagnostic.swift",
      enclosingTypeName: "Diagnostic",
      names: ["description"]
    ),
    .init(
      fileName: "BylawsFileError.swift",
      enclosingTypeName: "BylawsFileError",
      names: ["description"]
    ),
    .init(
      fileName: "Actor.swift",
      enclosingTypeName: "Actor",
      names: ["storage"]
    ),
    .init(
      fileName: "Class.swift",
      enclosingTypeName: "Class",
      names: ["storage"]
    ),
    .init(
      fileName: "Enum.swift",
      enclosingTypeName: "Enum",
      names: ["storage"]
    ),
    .init(
      fileName: "Struct.swift",
      enclosingTypeName: "Struct",
      names: ["storage"]
    ),
    .init(
      fileName: "EnumCase.swift",
      enclosingTypeName: "EnumCase",
      names: ["location", "name"]
    ),
    .init(
      fileName: "Extension.swift",
      enclosingTypeName: "Extension",
      names: ["location"]
    ),
    .init(
      fileName: "Function.swift",
      enclosingTypeName: "Function",
      names: ["attributes", "documentation", "location", "name", "visibility"]
    ),
    .init(
      fileName: "FunctionCall.swift",
      enclosingTypeName: "FunctionCall",
      names: ["location"]
    ),
    .init(
      fileName: "Import.swift",
      enclosingTypeName: "Import",
      names: ["location"]
    ),
    .init(
      fileName: "Initializer.swift",
      enclosingTypeName: "Initializer",
      names: ["attributes", "documentation", "location", "visibility"]
    ),
    .init(
      fileName: "NominalTypeStorage.swift",
      enclosingTypeName: "NominalTypeDeclaration",
      names: nominalTypeStorageNames
    ),
    .init(
      fileName: "Property.swift",
      enclosingTypeName: "Property",
      names: ["attributes", "documentation", "location", "name", "visibility"]
    ),
    .init(
      fileName: "ProtocolDeclaration.swift",
      enclosingTypeName: "ProtocolDeclaration",
      names: modelPropertyNames
    ),
    .init(
      fileName: "Typealias.swift",
      enclosingTypeName: "Typealias",
      names: ["attributes", "documentation", "location", "name", "visibility"]
    ),
    .init(
      fileName: "TestConformances.swift",
      enclosingTypeName: "CustomTestStringConvertible",
      names: ["testDescription"]
    ),
  ]

  private static let inheritedInitializerDocumentation: Set<FunctionWitness> = [
    .init(
      fileName: "Glob.swift",
      enclosingTypeName: "Glob",
      name: "init",
      labels: ["stringLiteral"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "Rule.ID",
      name: "init",
      labels: ["from"]
    ),
    .init(
      fileName: "Rule.swift",
      enclosingTypeName: "Rule.ID",
      name: "init",
      labels: ["stringLiteral"]
    ),
    .init(
      fileName: "SymbolRole.swift",
      enclosingTypeName: "SymbolRole",
      name: "init",
      labels: ["rawValue"]
    ),
    .init(
      fileName: "Violations.swift",
      enclosingTypeName: "Violations",
      name: "init",
      labels: ["from"]
    ),
  ]

  private static func inheritsFunctionDocumentation(_ function: Function)
    -> Bool
  {
    inheritedFunctionDocumentation.contains(FunctionWitness(
      fileName: function.location.fileName,
      enclosingTypeName: function.enclosingTypeName ?? "",
      name: function.name,
      labels: function.parameters.compactMap(\.label)
    ))
  }

  private static func inheritsPropertyDocumentation(_ property: Property)
    -> Bool
  {
    inheritedPropertyDocumentation.contains { group in
      group.fileName == property.location.fileName
        && group.enclosingTypeName == property.enclosingTypeName
        && group.names.contains(property.name)
    }
  }

  private static func inheritsInitializerDocumentation(
    _ initializer: Initializer
  ) -> Bool {
    inheritedInitializerDocumentation.contains(FunctionWitness(
      fileName: initializer.location.fileName,
      enclosingTypeName: initializer.enclosingTypeName ?? "",
      name: "init",
      labels: initializer.parameters.compactMap(\.label)
    ))
  }

  private struct FunctionWitness: Hashable {
    let fileName: String
    let enclosingTypeName: String
    let name: String
    let labels: [String]
  }

  private struct PropertyWitnessGroup {
    let fileName: String
    let enclosingTypeName: String
    let names: Set<String>
  }
}
