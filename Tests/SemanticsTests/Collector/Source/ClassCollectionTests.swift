import BylawsSemantics
import Testing

@Suite("Class collection")
struct ClassCollectionTests {
  @Test("Collector records class modifiers and inherited types")
  func extractsClassAttributes() throws {
    let file = try FileCollector.collect(
      source: """
      public final class HomeViewModel: BaseViewModel, Sendable {
          var title = ""
      }
      """,
      path: "/virtual/App/HomeViewModel.swift"
    )

    let homeViewModel = try #require(file.classes.first)
    #expect(file.classes.count == 1)
    #expect(homeViewModel.name == "HomeViewModel")
    #expect(homeViewModel.isFinal)
    #expect(homeViewModel.visibility == .public)
    #expect(homeViewModel.inherits(from: "BaseViewModel"))
    #expect(homeViewModel.inherits(from: "Sendable"))
    #expect(!homeViewModel.inherits(from: "NSObject"))
  }

  @Test("Collector records nested and top-level classes")
  func collectsNestedClasses() throws {
    let file = try FileCollector.collect(
      source: """
      class Outer {
          class Inner {}
      }
      enum Namespace {
          class Helper {}
      }
      """,
      path: "/virtual/App/Nesting.swift"
    )

    #expect(file.classes.map(\.name) == ["Outer", "Inner", "Helper"])
  }

  @Test("Locations point at the class name")
  func locatesDeclarations() throws {
    let file = try FileCollector.collect(
      source: """
      // A comment line.
      final class Positioned {}
      """,
      path: "/virtual/App/Positioned.swift"
    )

    let positioned = try #require(file.classes.first)
    #expect(positioned.location.line == 2)
    #expect(positioned.location.filePath == "/virtual/App/Positioned.swift")
    #expect(positioned.location.fileName == "Positioned.swift")
  }

  @Test("Default visibility is internal")
  func defaultsToInternal() throws {
    let file = try FileCollector.collect(
      source: "class Plain {}",
      path: "/virtual/Plain.swift"
    )
    let plain = try #require(file.classes.first)
    #expect(plain.visibility == .internal)
  }

  @Test("Unreadable file throws a typed error")
  func unreadableFileThrows() {
    #expect {
      try FileCollector.collect(fileAt: "/nonexistent/Missing.swift")
    } throws: { error in
      guard let error = error as? ParseError else { return false }
      guard case let .unreadable(path, reason) = error else { return false }
      return path == "/nonexistent/Missing.swift" && !reason.isEmpty
    }
  }
}
