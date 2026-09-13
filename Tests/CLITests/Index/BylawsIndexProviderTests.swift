import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsInterpreter
import Testing
@testable import BylawsRunner

@Suite("Index provider mappings")
struct BylawsIndexProviderTests {
  struct KindPair: CustomTestStringConvertible {
    let indexKind: IndexSymbol.Kind
    let runtimeKind: RuntimeIndexSymbol.Kind

    init(
      _ indexKind: IndexSymbol.Kind,
      _ runtimeKind: RuntimeIndexSymbol.Kind
    ) {
      self.indexKind = indexKind
      self.runtimeKind = runtimeKind
    }

    var testDescription: String { String(describing: runtimeKind) }

    static let cases: [Self] = [
      Self(.module, .module),
      Self(.enum, .enum),
      Self(.struct, .struct),
      Self(.class, .class),
      Self(.protocol, .protocol),
      Self(.extension, .extension),
      Self(.typealias, .typealias),
      Self(.function, .function),
      Self(.variable, .variable),
      Self(.instanceMethod, .instanceMethod),
      Self(.classMethod, .classMethod),
      Self(.staticMethod, .staticMethod),
      Self(.instanceProperty, .instanceProperty),
      Self(.classProperty, .classProperty),
      Self(.staticProperty, .staticProperty),
      Self(.initializer, .initializer),
      Self(.deinitializer, .deinitializer),
      Self(.enumCase, .enumCase),
      Self(.parameter, .parameter),
      Self(.other, .other),
    ]
  }

  struct RolePair: CustomTestStringConvertible {
    let indexRole: SymbolRole
    let runtimeRole: RuntimeSymbolRole

    init(_ indexRole: SymbolRole, _ runtimeRole: RuntimeSymbolRole) {
      self.indexRole = indexRole
      self.runtimeRole = runtimeRole
    }

    var testDescription: String { String(describing: runtimeRole) }

    static let cases: [Self] = [
      Self(.declaration, .declaration),
      Self(.definition, .definition),
      Self(.reference, .reference),
      Self(.read, .read),
      Self(.write, .write),
      Self(.call, .call),
      Self(.dynamic, .dynamic),
      Self(.implicit, .implicit),
      Self(.childOf, .childOf),
      Self(.baseOf, .baseOf),
      Self(.overrideOf, .overrideOf),
      Self(.receivedBy, .receivedBy),
      Self(.calledBy, .calledBy),
      Self(.extendedBy, .extendedBy),
      Self(.accessorOf, .accessorOf),
      Self(.containedBy, .containedBy),
      Self(.specializationOf, .specializationOf),
    ]
  }

  @Test(
    "Each index symbol kind reaches its runtime kind",
    arguments: KindPair.cases
  )
  func mapsSymbolKinds(_ pair: KindPair) {
    #expect(
      BylawsIndexProvider().runtimeKind(pair.indexKind) == pair.runtimeKind
    )
  }

  @Test(
    "Each index role reaches its runtime role alone",
    arguments: RolePair.cases
  )
  func mapsSymbolRoles(_ pair: RolePair) {
    #expect(
      BylawsIndexProvider().runtimeRoles(pair.indexRole) == [pair.runtimeRole]
    )
  }

  @Test("The mappings cover every runtime kind and role")
  func mappingsAreComplete() {
    #expect(
      Set(KindPair.cases.map(\.runtimeKind))
        == Set(RuntimeIndexSymbol.Kind.allCases)
    )
    #expect(
      Set(RolePair.cases.map(\.runtimeRole)) == Set(RuntimeSymbolRole.allCases)
    )
  }

  @Test("A combined role set maps to every runtime role")
  func mapsCombinedRoles() {
    let roles = BylawsIndexProvider().runtimeRoles(
      [.definition, .reference, .dynamic]
    )

    #expect(roles == [.definition, .reference, .dynamic])
  }

  @Test(
    "An indexed layering error keeps its case when the runtime maps it",
    arguments: [
      (
        IndexedLayeringError.invalidLayering(.duplicateLayer(name: "Core")),
        RuntimeIndexError.invalidLayering(.duplicateLayer(name: "Core"))
      ),
      (
        .unreadableCodebase(.notADirectory(path: "/project/Package.swift")),
        .unreadableCodebase(.notADirectory(path: "/project/Package.swift"))
      ),
      (
        .indexUnavailable(.missingStore(searched: ["/project/.build"])),
        .indexUnavailable(
          reason: IndexStoreError.missingStore(searched: ["/project/.build"])
            .description
        )
      ),
    ]
  )
  func mapsIndexedLayeringErrors(
    error: IndexedLayeringError,
    expected: RuntimeIndexError
  ) {
    #expect(RuntimeIndexError(error) == expected)
  }

  @Test(
    "A project index error keeps its case when the runtime maps it",
    arguments: [
      (
        ProjectIndexError.unreadableCodebase(
          .notADirectory(path: "/project/Package.swift")
        ),
        RuntimeIndexError.unreadableCodebase(
          .notADirectory(path: "/project/Package.swift")
        )
      ),
      (
        .indexUnavailable(.missingStore(searched: ["/project/.build"])),
        .indexUnavailable(
          reason: IndexStoreError.missingStore(searched: ["/project/.build"])
            .description
        )
      ),
    ]
  )
  func mapsProjectIndexErrors(
    error: ProjectIndexError,
    expected: RuntimeIndexError
  ) {
    #expect(RuntimeIndexError(error) == expected)
  }
}
