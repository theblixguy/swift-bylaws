package import BylawsCore
package import BylawsSemantics

package enum RuntimeIndexQuery: String, CaseIterable, Hashable, Sendable {
  case conformers
  case definitions
  case directConformers
  case occurrences
  case references
}

package protocol RuntimeIndexProvider: Sendable {
  func checkDependencies(
    from sourcePatterns: [String],
    allowingReferencesTo destinationPatterns: [String],
    allowingWithinFoldersMatching folderPattern: String?,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings

  func checkDependencyCycles(
    between groups: [DependencyGroup],
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings

  func indexedFindings(
    of layering: Layering,
    in index: RuntimeProjectIndex,
    location: DeclarationLocation
  ) async throws(RuntimeIndexError) -> Rule.Findings

  func references(
    _ query: RuntimeIndexQuery,
    of symbolName: String,
    in index: RuntimeProjectIndex
  ) async throws(RuntimeIndexError) -> [RuntimeIndexReference]
}

package enum RuntimeIndexError: Error, Sendable, Hashable {
  case dependencyCheck(reason: String)
  case invalidLayering(LayeringError)
  case unreadableCodebase(CodebaseError)
  case indexUnavailable(reason: String)
}

extension RuntimeIndexError: CustomStringConvertible {
  package var description: String {
    switch self {
    case let .dependencyCheck(reason): reason
    case let .invalidLayering(error): error.description
    case let .unreadableCodebase(error): error.description
    case let .indexUnavailable(reason): reason
    }
  }
}

package enum RuntimeSymbolRole: String, CaseIterable, Hashable, Sendable {
  case declaration
  case definition
  case reference
  case read
  case write
  case call
  case dynamic
  case implicit
  case childOf
  case baseOf
  case overrideOf
  case receivedBy
  case calledBy
  case extendedBy
  case accessorOf
  case containedBy
  case specializationOf
}

package struct RuntimeIndexReference: Sendable, Equatable {
  package let symbol: RuntimeIndexSymbol
  package let module: String
  package let file: String
  package let line: Int
  package let column: Int
  package let roles: Set<RuntimeSymbolRole>

  package init(
    symbol: RuntimeIndexSymbol,
    module: String,
    file: String,
    line: Int,
    column: Int,
    roles: Set<RuntimeSymbolRole>
  ) {
    self.symbol = symbol
    self.module = module
    self.file = file
    self.line = line
    self.column = column
    self.roles = roles
  }

  var offender: Offender {
    Offender(
      description: symbol.name,
      name: symbol.name,
      location: DeclarationLocation(
        filePath: file,
        line: line,
        column: column
      )
    )
  }
}

package struct RuntimeIndexSymbol: Sendable, Equatable {
  package enum Kind: String, CaseIterable, Hashable, Sendable {
    case module
    case `enum`
    case `struct`
    case `class`
    case `protocol`
    case `extension`
    case `typealias`
    case function
    case variable
    case instanceMethod
    case classMethod
    case staticMethod
    case instanceProperty
    case classProperty
    case staticProperty
    case initializer
    case deinitializer
    case enumCase
    case parameter
    case other
  }

  package let usr: String
  package let name: String
  package let kind: Kind

  package init(usr: String, name: String, kind: Kind) {
    self.usr = usr
    self.name = name
    self.kind = kind
  }
}

package struct RuntimeProjectIndex: Sendable {
  package let codebase: Codebase
  package let modules: Set<String>?
  package let unitOutputFiles: Set<String>?

  package init(
    codebase: Codebase,
    modules: Set<String>?,
    unitOutputFiles: Set<String>?
  ) {
    self.codebase = codebase
    self.modules = modules
    self.unitOutputFiles = unitOutputFiles
  }
}
