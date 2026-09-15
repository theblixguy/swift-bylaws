import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Folder rule overrides")
struct FolderOverrideTests {
  @Test("Nearest override replaces parent rule within its folder")
  func nestedOverrides() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Rule("documented") { codebase.classes.violations(of: .hasDocumentation) }
      """,
      "Modules/Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Rule("classes", "Classes final", hint: "make the class final") {
        codebase.classes.violations(of: .isFinal)
      }
      """,
      "Modules/Sources/Parent.swift": "class Parent {}",
      "Modules/Billing/Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Override("classes", reason: "billing uses public classes", enforcement: .advisory, hint: "make the class public") {
        codebase.classes.violations(of: .isPublic)
      }
      """,
      "Modules/Billing/Sources/Invoice.swift": "class Invoice {}",
      "Modules/Billing/Legacy/Bylaws.swift": """
      let codebase = Codebase(including: ["Sources/**"])
      Override("classes", reason: "legacy classes use documentation") {
        codebase.classes.violations(of: .hasDocumentation)
      }
      """,
      "Modules/Billing/Legacy/Sources/Legacy.swift": "class Legacy {}",
      "Modules/BillingKit/Sources/Sibling.swift": "class Sibling {}",
    ])

    let program = try await discoveredProgram(in: project)
    let parent = try #require(program.rules.first { $0.id == "classes" })
    let billing = try #require(program.rules
      .first { $0.location.filePath.hasSuffix("Billing/Bylaws.swift") })
    let legacy = try #require(program.rules
      .first { $0.location.filePath.hasSuffix("Legacy/Bylaws.swift") })

    #expect(try await parent.violations().offenders.compactMap(\.name)
      .sorted() == [
        "Parent",
        "Sibling",
      ])
    #expect(try await billing.violations().offenders
      .compactMap(\.name) == ["Invoice"])
    #expect(try await legacy.violations().offenders
      .compactMap(\.name) == ["Legacy"])
    #expect(legacy.name == "Classes final")
    #expect(legacy.enforcement == .advisory)
    #expect(legacy.hint == "make the class public")
    #expect(Set(program
        .rules(applyingTo: "Modules/Billing/Legacy/Sources/Legacy.swift")
        .map(\.id)) == ["classes", "documented"])
  }

  @Test("Reject overrides of sibling rules")
  func siblingRule() async throws {
    let project = try TemporaryProject(files: [
      "Modules/Billing/Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Rule("classes") { codebase.classes.violations(of: .isFinal) }
      """,
      "Modules/BillingKit/Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Override("classes", reason: "different folder") {
        codebase.classes.violations(of: .isPublic)
      }
      """,
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.count == 1)
    #expect(program.errors.first?.location.filePath == project
      .fileURL(for: "Modules/BillingKit/Bylaws.swift").path)
  }

  @Test("Keep parent rule when child override cannot compile")
  func failedOverride() async throws {
    let project = try TemporaryProject(files: [
      "Modules/Bylaws.swift": """
      let codebase = Codebase(including: ["**"])
      Rule("classes") { codebase.classes.violations(of: .isFinal) }
      """,
      "Modules/Billing/Bylaws.swift": """
      Override("classes", reason: "billing uses public classes") {
        missing.classes.violations(of: .isPublic)
      }
      """,
      "Modules/Billing/Invoice.swift": "class Invoice {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let rule = try #require(program
      .rules(applyingTo: "Modules/Billing/Invoice.swift").first)

    #expect(program.errors.count == 1)
    #expect(rule.location.filePath == project
      .fileURL(for: "Modules/Bylaws.swift").path)
    #expect(try await rule.violations().offenders
      .compactMap(\.name) == ["Invoice"])
  }
}
