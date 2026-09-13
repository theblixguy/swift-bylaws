import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Interpreted rules")
struct InterpreterRuleTests {
  @Test("A rules file loads and its rule finds the violation")
  func loadsAndRuns() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      import Bylaws

      let app = Codebase(
        including: ["Sources/**"],
        excluding: ["Sources/Generated/**"]
      )

      Rule("viewmodel-inheritance", "ViewModels inherit from BaseViewModel") {
        app.classes.suffixed("ViewModel").violations(of: .inherits(from: "BaseViewModel"))
      }
      """,
      "Sources/App/Screens.swift": """
      class HomeViewModel {}
      final class SettingsViewModel: BaseViewModel {}
      """,
      "Sources/Generated/Legacy.swift": "class LegacyViewModel {}",
    ])

    let program = try await discoveredProgram(in: project)
    let rule = try #require(program.rules.first)
    #expect(rule.id == "viewmodel-inheritance")
    #expect(rule.location.line == 8)

    let violations = try await rule.violations()
    #expect(violations.count == 1)
    #expect(violations.checkedCount == 2)
    let offender = try #require(violations.offenders.first)
    #expect(offender.description.contains("HomeViewModel"))
  }

  @Test("A rule can use one string as its ID and name")
  func readsOneStringRule() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule("final-classes") {
        app.classes.violations(of: .isFinal)
      }
      """,
      "Sources/App/A.swift": "final class A {}",
    ])

    let program = try await discoveredProgram(in: project)
    let rule = try #require(program.rules.first)
    #expect(rule.id == "final-classes")
    #expect(rule.name == "final-classes")
  }

  @Test(
    "Interpreter treats a try await call chain like the same chain without it"
  )
  func acceptsTryAwait() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule("no-print", "Sources stay free of print") {
        try await app.calls.violations(matching: .references("print"))
      }
      """,
      "Sources/App/Logger.swift": "func log() { print(\"hello\") }",
    ])

    let program = try await discoveredProgram(in: project)

    let violations = try await #require(program.rules.first).violations()
    #expect(violations.count == 1)
  }

  @Test("Interpreter supports filters, bans and matcher composition")
  func interpretsComposition() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      Rule("domain-ui-free", "The domain layer stays free of UI frameworks") {
        app.files.under("Sources/Domain").violations(matching: .imports("UIKit") || .imports("SwiftUI"))
      }

      Rule("final-screens", "Screen classes say final or public") {
        app.classes.suffixed("Screen").violations(of: .isFinal || .isPublic)
      }
      """,
      "Sources/Domain/User.swift": "import UIKit\nstruct User {}",
      "Sources/Domain/Order.swift": "import Foundation\nstruct Order {}",
      "Sources/UI/Home.swift": """
      import SwiftUI
      class HomeScreen {}
      final class SettingsScreen {}
      """,
    ])

    let program = try await discoveredProgram(in: project)
    #expect(program.rules.count == 2)

    let imports = try await #require(program.rules.first).violations()
    #expect(imports.count == 1)
    let importOffender = try #require(imports.offenders.first)
    #expect(importOffender.location.filePath.hasSuffix("User.swift"))

    let finals = try await #require(program.rules.last).violations()
    #expect(finals.count == 1)
    let finalOffender = try #require(finals.offenders.first)
    #expect(finalOffender.description.contains("HomeScreen"))
  }

  @Test("Interpreter reads 'mayImport: .any' as the any policy")
  func interpretsAnyPolicy() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      let layering = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: .any)
      )

      Rule("layering", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Sources/Domain/User.swift": "struct User {}",
      "Sources/UI/Home.swift": "import Domain\nstruct Home {}",
    ])

    let program = try await discoveredProgram(in: project)
    let violations = try await #require(program.rules.first).violations()
    #expect(violations.isEmpty)
  }

  @Test("A missing mustImport edge reports at the rule declaration")
  func layeringMissingImportReports() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      let layering = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"], mustImport: ["Domain"])
      )

      Rule("layering", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Sources/Domain/User.swift": "struct User {}",
      "Sources/UI/Home.swift": "struct Home {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let violations = try await #require(program.rules.first).violations()
    let offender = try #require(violations.offenders.first)
    #expect(offender.description.contains("does not import 'Domain'"))
    #expect(offender.location.filePath.hasSuffix("Bylaws.swift"))
    #expect(offender.name == "UI imports Domain")
  }

  @Test("A layer can forbid an import by its declared module")
  func interpretsForbiddenModule() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      let layering = Layering(
        Layer(
          "Domain",
          files: ["Sources/Domain/**"],
          modules: ["DomainAPI"]
        ),
        Layer(
          "UI",
          files: ["Sources/UI/**"],
          mayImport: .any,
          mustNotImport: ["Domain"]
        )
      )

      Rule("layering", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Sources/Domain/User.swift": "struct User {}",
      "Sources/UI/Home.swift": "import DomainAPI\nstruct Home {}",
    ])

    let program = try await discoveredProgram(in: project)
    let violations = try await #require(program.rules.first).violations()
    #expect(violations.count == 1)
    let offender = try #require(violations.offenders.first)
    #expect(offender.name == "DomainAPI")
    #expect(offender.location.filePath.hasSuffix("Home.swift"))
  }

  @Test("An empty layer reports a warning rather than a violation")
  func reportsEmptyLayers() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      let layering = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("Ghost", files: ["Sources/Ghost/**"], mayImport: ["Domain"])
      )

      Rule("layering", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Sources/Domain/User.swift": "struct User {}",
    ])

    let program = try await discoveredProgram(in: project)
    let findings = try await #require(program.rules.first).findings()

    #expect(findings.violations.isEmpty)
    let warning = try #require(findings.warnings.first)
    #expect(
      warning.message == "layer 'Ghost' matched no files"
    )
    #expect(warning.location.filePath.hasSuffix("Bylaws.swift"))
  }

  @Test("Interpreter accepts a layering binding in 'violations(of:)'")
  func interpretsLayering() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])

      let layering = Layering(
        Layer("Domain", files: ["Sources/Domain/**"]),
        Layer("UI", files: ["Sources/UI/**"], mayImport: ["Domain"])
      )

      Rule("layering", "The declared layering holds") {
        app.checkLayering(layering)
      }
      """,
      "Sources/Domain/User.swift": "import UI\nstruct User {}",
      "Sources/UI/Home.swift": "import Domain\nstruct Home {}",
    ])

    let program = try await discoveredProgram(in: project)

    let violations = try await #require(program.rules.first).violations()
    #expect(violations.count == 1)
    let offender = try #require(violations.offenders.first)
    #expect(offender.location.filePath.hasSuffix("User.swift"))
  }

  @Test("An advisory rule remains advisory after interpretation")
  func readsEnforcement() async throws {
    let project = try advisoryDocumentationProject()

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    #expect(program.rules.first?.enforcement == .advisory)
  }
}
