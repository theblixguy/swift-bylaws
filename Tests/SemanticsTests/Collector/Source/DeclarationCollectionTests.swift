import BylawsSemantics
import Testing

@Suite("Declaration collection")
struct DeclarationCollectionTests {
  @Test("Collector records structs, enums and protocols with their modifiers")
  func extractsTypeDeclarations() throws {
    let file = try FileCollector.collect(
      source: """
      public struct Event: Equatable {}
      enum Direction: CaseIterable {
          case north, south
      }
      package protocol Routing: AnyObject {}
      """,
      path: "/virtual/App/Types.swift"
    )

    let event = try #require(file.structs.first)
    #expect(event.visibility == .public)
    #expect(event.inherits(from: "Equatable"))

    let direction = try #require(file.enums.first)
    #expect(direction.cases.map(\.name) == ["north", "south"])

    let routing = try #require(file.protocols.first)
    #expect(routing.visibility == .package)
    #expect(routing.inherits(from: "AnyObject"))
  }

  @Test("Collector records function parameters, return types and scope")
  func extractsFunctions() throws {
    let file = try FileCollector.collect(
      source: """
      struct Calculator {
          static func add(_ a: Int, to b: Int) -> Int { a + b }
      }
      func topLevel() {}
      """,
      path: "/virtual/App/Calculator.swift"
    )

    let add = try #require(file.functions.first { $0.name == "add" })
    #expect(add.isStatic)
    #expect(add.returnTypeName == "Int")
    #expect(add.enclosingTypeName == "Calculator")
    #expect(add.parameters.map(\.label) == [nil, "to"])
    #expect(add.parameters.map(\.name) == ["a", "b"])
    #expect(add.parameters.map(\.typeName) == ["Int", "Int"])

    let topLevel = try #require(file.functions.first { $0.name == "topLevel" })
    #expect(topLevel.enclosingTypeName == nil)
    #expect(topLevel.returnTypeName == nil)
  }

  @Test("Collector records property bindings, attributes and constancy")
  func extractsProperties() throws {
    let file = try FileCollector.collect(
      source: """
      final class Store {
          @Published var items: [String] = []
          let limit: Int = 10
          static var shared: Store?
      }
      """,
      path: "/virtual/App/Store.swift"
    )

    let items = try #require(file.properties.first { $0.name == "items" })
    #expect(items.hasAttribute("@Published"))
    #expect(items.hasAttribute("Published"))
    #expect(!items.isConstant)
    #expect(items.typeName == "[String]")

    let limit = try #require(file.properties.first { $0.name == "limit" })
    #expect(limit.isConstant)

    let shared = try #require(file.properties.first { $0.name == "shared" })
    #expect(shared.isStatic)
  }

  @Test("A trailing annotation applies to its binding group")
  func sharedBindingAnnotations() throws {
    let file = try FileCollector.collect(
      source: """
      var first, second: Int
      var inferred = 1, named: String
      var third, fourth: Double = 0
      """,
      path: "/virtual/App/Bindings.swift"
    )

    #expect(file.properties.map(\.typeName) == [
      "Int", "Int", nil, "String", "Double", "Double",
    ])
  }

  @Test("Collector records explicit Void return clauses")
  func explicitVoidReturnTypes() throws {
    let file = try FileCollector.collect(
      source: """
      func inferred() {}
      func named() -> Void {}
      func tuple() -> () {}
      """,
      path: "/virtual/App/Returns.swift"
    )

    #expect(file.functions.map(\.returnTypeName) == [nil, "Void", "()"])
  }

  @Test("Collector assigns each conditional enum its own cases")
  func conditionalEnumsKeepTheirCases() throws {
    let file = try FileCollector.collect(
      source: """
      #if os(macOS)
      enum Platform { case macOS }
      #else
      enum Platform { case other }
      #endif
      """,
      path: "/virtual/App/Platform.swift"
    )

    #expect(file.enums.map { $0.cases.map(\.name) } == [["macOS"], ["other"]])
  }

  @Test("Collector records initialiser parameters and failability")
  func extractsInitializers() throws {
    let file = try FileCollector.collect(
      source: """
      struct Identifier {
          init?(rawValue: String) { nil }
      }
      """,
      path: "/virtual/App/Identifier.swift"
    )

    let initializer = try #require(file.initializers.first)
    #expect(initializer.isFailable)
    #expect(initializer.parameters.map(\.label) == ["rawValue"])
    #expect(initializer.enclosingTypeName == "Identifier")
  }

  @Test("Collector records import paths")
  func extractsImports() throws {
    let file = try FileCollector.collect(
      source: """
      import Foundation
      import UIKit.UIView
      """,
      path: "/virtual/App/Imports.swift"
    )

    #expect(file.imports.map(\.name) == ["Foundation", "UIKit.UIView"])
    #expect(file.imports("UIKit"))
    #expect(file.imports("Foundation"))
    #expect(!file.imports("SwiftUI"))
  }

  @Test("Collector records import visibility, attributes and kind")
  func extractsImportDetails() throws {
    let file = try FileCollector.collect(
      source: """
      @preconcurrency import Dispatch
      private import CryptoKit
      public import struct Foundation.Date
      @testable import MyAppCore
      """,
      path: "/virtual/App/ScopedImports.swift"
    )

    let dispatch = try #require(file.imports.first { $0.name == "Dispatch" })
    #expect(dispatch.hasAttribute("preconcurrency"))
    #expect(dispatch.kind == nil)
    #expect(dispatch.visibility == .internal)

    let cryptoKit = try #require(file.imports.first { $0.name == "CryptoKit" })
    #expect(cryptoKit.visibility == .private)

    let date = try #require(
      file.imports.first { $0.name == "Foundation.Date" }
    )
    #expect(date.kind == .struct)
    #expect(date.visibility == .public)
    #expect(date.moduleName == "Foundation")

    let appCore = try #require(file.imports.first { $0.name == "MyAppCore" })
    #expect(appCore.hasAttribute("@testable"))
  }

  @Test("Collector records extension visibility and attributes")
  func extractsExtensionDetails() throws {
    let file = try FileCollector.collect(
      source: """
      @MainActor public extension Store {
        func reload() {}
        private func reset() {}
      }
      """,
      path: "/virtual/App/Store+MainActor.swift"
    )

    let storeExtension = try #require(file.extensions.first)
    #expect(storeExtension.hasAttribute("MainActor"))
    #expect(storeExtension.isPublic)
    let reload = try #require(file.functions.first { $0.name == "reload" })
    #expect(reload.visibility == .public)
    let reset = try #require(file.functions.first { $0.name == "reset" })
    #expect(reset.visibility == .private)
  }

  @Test("Public protocol requirements inherit the protocol visibility")
  func publicProtocolRequirementsArePublic() throws {
    let file = try FileCollector.collect(
      source: """
      public protocol Store {
        var count: Int { get }
        func reload()
      }
      """,
      path: "/virtual/App/Store.swift"
    )

    let store = try #require(file.protocols.first)
    #expect(store.requiredProperties.first?.visibility == .public)
    #expect(store.requiredFunctions.first?.visibility == .public)
  }
}
