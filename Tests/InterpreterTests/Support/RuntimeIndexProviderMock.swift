import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import Testing

struct RuntimeIndexProviderMock: RuntimeIndexProvider {
  func checkDependencies(
    from sourcePatterns: [String],
    allowingReferencesTo destinationPatterns: [String],
    allowingWithinFoldersMatching folderPattern: String?,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async -> Rule.Findings {
    #expect(sourcePatterns == ["Sources/Components/**"])
    #expect(destinationPatterns == [
      "Sources/Contracts/**",
      "Sources/Common/**",
    ])
    #expect(folderPattern == expectedFolderPattern)
    #expect(index.modules == ["App"])
    #expect(index.unitOutputFiles == ["/build/App.o"])
    return Rule.Findings(violations: Violations(
      rule: "reference only permitted files",
      offenders: [],
      checkedCount: 2
    ))
  }

  func checkDependencyCycles(
    between groups: [DependencyGroup],
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async -> Rule.Findings {
    #expect(groups == [DependencyGroup(
      "Components",
      files: ["Sources/Components/**"]
    )])
    #expect(index.modules == ["App"])
    #expect(index.unitOutputFiles == ["/build/App.o"])
    return Rule.Findings(violations: Violations(
      rule: "avoid dependency cycles", offenders: [], checkedCount: 3
    ))
  }

  let expectedQuery: RuntimeIndexQuery?
  let expectedFolderPattern: String?
  let suppliedReferences: [RuntimeIndexReference]?

  init(
    expectedQuery: RuntimeIndexQuery? = nil,
    expectedFolderPattern: String? = nil,
    references: [RuntimeIndexReference]? = nil
  ) {
    self.expectedQuery = expectedQuery
    self.expectedFolderPattern = expectedFolderPattern
    suppliedReferences = references
  }

  func indexedFindings(
    of layering: Layering,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async -> Rule.Findings {
    Rule.Findings(
      violations: Violations(
        rule: "follow the declared layering",
        offenders: [
          Offender(
            description: "ForbiddenUse in Domain depends on UI",
            name: "ForbiddenUse",
            location: location
          ),
        ],
        checkedCount: 1
      )
    )
  }

  func references(
    _ query: RuntimeIndexQuery,
    of symbolName: String,
    in index: RuntimeProjectIndex
  ) async -> [RuntimeIndexReference] {
    if let expectedQuery {
      #expect(query == expectedQuery)
      #expect(symbolName == "Located")
      #expect(index.modules == ["BylawsSemantics"])
      #expect(index.unitOutputFiles == nil)
    }
    return references
  }

  func occurrences(
    at location: DeclarationLocation,
    in index: RuntimeProjectIndex
  ) async -> [RuntimeIndexReference] {
    references.filter {
      $0.file == location.filePath && $0.line == location.line && $0
        .column == location.column
    }
  }

  func definitions(in index: RuntimeProjectIndex) async
    -> [RuntimeIndexReference]
  {
    references.filter {
      $0.roles.contains(.definition) || $0.roles.contains(.declaration)
    }
  }

  func references(
    to definitions: [RuntimeIndexReference],
    in index: RuntimeProjectIndex
  ) async -> [RuntimeIndexReference] {
    references.filter { reference in
      reference.roles.contains(.reference)
        && !reference.roles.contains(.definition)
        && definitions.contains { $0.symbol.usr == reference.symbol.usr }
    }
  }

  private var references: [RuntimeIndexReference] {
    suppliedReferences ?? [
      reference(name: "CoreConformer", module: "BylawsSemantics", line: 3),
      reference(name: "UIConformer", module: "UI", line: 8),
    ]
  }

  private func reference(
    name: String,
    module: String,
    line: Int
  ) -> RuntimeIndexReference {
    RuntimeIndexReference(
      symbol: RuntimeIndexSymbol(
        usr: "s:\(module).\(name)",
        name: name,
        kind: .struct
      ),
      module: module,
      file: "/project/Sources/\(module)/\(name).swift",
      line: line,
      column: 7,
      roles: [.definition]
    )
  }
}
