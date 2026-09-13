import Bylaws
import Testing

@Suite("Type identity", .tags(.architecture))
struct TypeIdentityTests {
  @Test("Qualified parents keep their inheritance chain", arguments: [
    "Legacy.Base", "Parent",
  ])
  func qualifiedParent(_ parent: String) async throws {
    let codebase = Codebase(root: .sources([
      "Types.swift": """
      class Base: FirstRoot {}
      enum Legacy { class Base: SecondRoot {} }
      typealias Parent = Legacy.Base
      class Child: \(parent) {}
      """,
    ]))
    let child = try #require(try await codebase.classes.named("Child").first)
    #expect(child.inherits(from: "SecondRoot"))
    #expect(child.inherits(from: "Legacy.Base"))
    #expect(child.inherits(from: "Base"))
    #expect(!child.inherits(from: "FirstRoot"))
  }

  @Test("An extension of a top-level type leaves a namesake alone")
  func topLevelExtensionStaysTopLevel() async throws {
    let topLevel = try await user(nestedIn: nil)
    let nested = try await user(nestedIn: "Legacy")
    #expect(topLevel.conforms(to: "Identifiable"))
    #expect(!nested.conforms(to: "Identifiable"))
  }

  @Test("A qualified extension applies only to the nested type")
  func qualifiedExtensionReachesTheNestedType() async throws {
    let topLevel = try await user(nestedIn: nil)
    let nested = try await user(nestedIn: "Legacy")
    #expect(nested.conforms(to: "Codable"))
    #expect(!topLevel.conforms(to: "Codable"))
  }

  private let codebase = Codebase(root: .sources([
    "Sources/Users.swift": """
    struct User {}
    enum Legacy {
      struct User {}
    }
    """,
    "Sources/Conformances.swift": """
    extension User: Identifiable {}
    extension Legacy.User: Codable {}
    """,
  ]))

  private func user(nestedIn enclosingTypeName: String?) async throws
    -> Struct
  {
    let users = try await codebase.structs.named("User")
    return try #require(
      users.first { $0.enclosingTypeName == enclosingTypeName }
    )
  }
}
