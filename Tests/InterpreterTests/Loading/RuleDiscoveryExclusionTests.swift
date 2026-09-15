import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule discovery exclusions")
struct RuleDiscoveryExclusionTests {
  @Test(
    "Skip excluded folders and retain sibling rules",
    .bug("https://github.com/theblixguy/swift-bylaws/issues/13"),
    arguments: ["Vendor", "Vendor/**", "Ven?or", "**/Vendor"]
  )
  func excludedFolders(pattern: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      RuleDiscovery(excluding: ["\(pattern)"])
      """,
      "Vendor/Nested/Package.swift": "",
      "Vendor/Nested/Bylaws.swift": "this must not be parsed",
      "VendorKit/Package.swift": "",
      "VendorKit/Bylaws.swift": """
      let library = Codebase(including: ["Sources/**"])
      Rule("sibling") { library.classes.violations(of: .isFinal) }
      """,
      "VendorKit/Sources/Library.swift": "final class Library {}",
      "App/Package.swift": "",
      "App/Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "App/Sources/Model.swift": "class Model {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["final-classes", "sibling"])
    let rule = try #require(program.rules.first)
    #expect(try await rule.violations().count == 1)
  }

  @Test("Skip baselines in excluded folders")
  func excludedBaselines() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      RuleDiscovery(excluding: ["**/Generated"])
      """,
      "Modules/Generated/Nested/Package.swift": "",
      "Modules/Generated/Nested/Bylaws.baseline.swift": "cannot parse this",
      "Bylaws.baseline.swift": BaselineFile.render(name: "root", entries: []),
    ])

    let result = await DiscoveredBaselines.discovered(
      atRoot: project.rootURL.path
    )

    #expect(result.diagnostics.isEmpty)
    #expect(result.baselines.map(\.relativeDirectory) == [""])
  }

  @Test("Retain root rules and source selection")
  func sourceSelection() async throws {
    let project = try TemporaryProject(files: [
      "Package.swift": "",
      "Bylaws.swift": """
      RuleDiscovery(excluding: ["**"])
      let app = Codebase(including: ["Vendor/**/Sources/**"])
      Rule("final-classes") { app.classes.violations(of: .isFinal) }
      """,
      "Vendor/Module/Package.swift": "",
      "Vendor/Module/Bylaws.swift": "cannot parse this",
      "Vendor/Module/Sources/Model.swift": "class Model {}",
    ])

    let rules = try await Rule.discovered(
      above: project.fileURL(for: "Tests/Rules.swift").path
    )

    #expect(rules.map(\.id) == ["final-classes"])
    let rule = try #require(rules.first)
    #expect(try await rule.violations().offenders
      .compactMap(\.name) == ["Model"])
  }

  @Test("Read discovery settings from editor text")
  func editorText() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [])",
      "Vendor/Module/Package.swift": "",
      "Vendor/Module/Bylaws.swift": "cannot parse this",
    ])

    let program = await RuleProgram.discovered(
      atRoot: LexicalFilePath(project.rootURL.path),
      parseCachePolicy: .disabled,
      overlay: SourceOverlay([
        project.fileURL(for: "Bylaws.swift").path: """
        RuleDiscovery(excluding: ["Vendor"])
        """,
      ])
    )

    #expect(program.diagnostics.isEmpty)
    #expect(program.ruleFileStatus == .found)
  }

  @Test("Load explicit rules from excluded folders")
  func explicitFiles() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [\"Vendor\"])",
      "Vendor/Bylaws.swift": """
      let library = Codebase(including: ["Sources/**"])
      Rule("vendor") { library.classes.violations(of: .isFinal) }
      """,
      "Vendor/Sources/Library.swift": "final class Library {}",
    ])

    let program = await RuleProgram.loaded(fromFiles: [
      project.fileURL(for: "Bylaws.swift").path,
      project.fileURL(for: "Vendor/Bylaws.swift").path,
    ])

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["vendor"])
  }

  @Test("Skip unreadable excluded folders")
  func unreadableFolder() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [\"Vendor\"])",
      "Vendor/Package.swift": "",
    ])
    let folder = project.fileURL(for: "Vendor").path
    try FileManager.default.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: folder
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: folder
      )
    }

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.diagnostics.isEmpty)
  }
}
