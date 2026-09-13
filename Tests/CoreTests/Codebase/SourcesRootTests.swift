import Bylaws
import Testing

@Suite("In-memory sources")
struct SourcesRootTests {
  @Test("A codebase parses from source strings")
  func parsesFromStrings() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/App/A.swift": "final class A {}",
      "Sources/App/B.swift": "class B: A {}",
    ]))
    let classes = try await codebase.classes
    #expect(classes.map(\.name).sorted() == ["A", "B"])
  }

  @Test("A matcher is testable against an inline codebase")
  func matcherIsTestable() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Domain/User.swift": "import UIKit\nstruct User {}",
      "Sources/Domain/Order.swift": "import Foundation\nstruct Order {}",
    ]))
    let violations = try await codebase.files
      .violations(matching: .imports("UIKit"))
    #expect(violations.count == 1)
    #expect(violations.checkedCount == 2)
  }

  @Test("An inline codebase can check layering rules")
  func layeringIsTestable() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Domain/User.swift": "struct User {}",
      "Sources/UI/HomeView.swift": "import Domain\nimport Data",
      "Sources/Data/Store.swift": "import Domain",
    ]))
    let layering = Layering(
      Layer("Domain", files: ["Sources/Domain/**"]),
      Layer("Data", files: ["Sources/Data/**"], mayImport: ["Domain"]),
      Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
    )
    let result = try await codebase.checkLayering(layering)
    #expect(result.violations.count == 1)
    #expect(result.violations.offenders.first?.moduleName == "Data")
  }

  @Test("Include and exclude globs narrow in-memory sources")
  func globsApply() async throws {
    let codebase = Codebase(
      root: .sources([
        "Sources/App/A.swift": "struct A {}",
        "Sources/Generated/G.swift": "struct G {}",
      ]),
      excluding: ["Sources/Generated/**"]
    )
    let structs = try await codebase.structs
    #expect(structs.map(\.name) == ["A"])
  }

  @Test("Path filters work on in-memory sources")
  func pathFiltersApply() async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Domain/User.swift": "struct User {}",
      "Sources/UI/HomeView.swift": "struct HomeView {}",
    ]))
    let domainFiles = try await codebase.files.under("Sources/Domain")
    #expect(domainFiles.map(\.name) == ["User.swift"])
  }

  @Test("A leading slash in a source key does not break path filters")
  func leadingSlashIsTrimmed() async throws {
    let codebase = Codebase(root: .sources([
      "/Sources/App/A.swift": "struct A {}",
    ]))
    let appFiles = try await codebase.files.under("Sources/App")
    #expect(appFiles.map(\.name) == ["A.swift"])
  }
}
