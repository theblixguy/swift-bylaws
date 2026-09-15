import BylawsCore
import BylawsInterpreter
import BylawsPaths
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule discovery configuration")
struct RuleDiscoveryConfigurationTests {
  @Test("Reject discovery bindings", arguments: [
    "let discovery =",
    "var discovery =",
    "let discovery: RuleDiscovery =",
    "let _ =",
  ])
  func boundDeclaration(binding: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "\(binding) RuleDiscovery(excluding: [\"Vendor\"])",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(!program.errors.isEmpty)
    #expect(program.errors.first?.location.line == 1)
  }

  @Test("Report unsupported discovery arguments", arguments: [
    "RuleDiscovery()",
    "RuleDiscovery(excluding: \"Vendor\")",
    "RuleDiscovery(excluding: folders)",
    "RuleDiscovery(excluding: [\"Vendor\"], excluding: [])",
    "RuleDiscovery(including: [\"Vendor\"])",
    #"RuleDiscovery(excluding: ["\(folder)"])"#,
  ])
  func unsupportedArguments(expression: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": expression,
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.map(\.message) == [
      "RuleDiscovery takes an 'excluding' array of string literals",
    ])
    #expect(program.errors.first?.location.line == 1)
    #expect(program.rules.isEmpty)
  }

  @Test("Report repeated discovery declarations")
  func repeatedDeclarations() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      RuleDiscovery(excluding: [])
      RuleDiscovery(excluding: ["Generated"])
      """,
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors
      .map(\.message) == ["RuleDiscovery must be declared once"])
    #expect(program.errors.first?.location.line == 2)
    #expect(program.errors.first?
      .hint == "combine the excluded folders in one declaration")
  }

  @Test("Report repeated declaration after unsupported arguments")
  func repeatedAfterArgumentError() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      RuleDiscovery(excluding: "Vendor")
      RuleDiscovery(excluding: ["Generated"])
      """,
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.map(\.message) == [
      "RuleDiscovery takes an 'excluding' array of string literals",
      "RuleDiscovery must be declared once",
    ])
    #expect(program.errors.map(\.location.line) == [1, 2])
  }

  @Test("Read standalone discovery settings")
  func standaloneDeclaration() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [\"Vendor\"])",
      "Vendor/Package.swift": "",
      "Vendor/Bylaws.swift": "cannot parse this",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.diagnostics.isEmpty)
    #expect(program.ruleFileStatus == .found)
  }

  @Test("Report package-local discovery settings")
  func packageSettings() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "",
      "Modules/Feature/Package.swift": "",
      "Modules/Feature/Bylaws.swift": "RuleDiscovery(excluding: [])",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors.map(\.message) == [
      "RuleDiscovery must be declared in the root Bylaws.swift",
    ])
    #expect(program.errors.first?.location.filePath == project.fileURL(
      for: "Modules/Feature/Bylaws.swift"
    ).path)
  }

  @Test("Retain built-in discovery exclusions")
  func builtInExclusions() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [])",
      ".build/Nested/Package.swift": "",
      ".build/Nested/Bylaws.swift": "cannot parse this",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.diagnostics.isEmpty)
  }

  @Test("Keep folder patterns in discovery settings")
  func nativeConfiguration() {
    #expect(RuleDiscovery(excluding: ["Vendor", "**/Generated"])
      .excludedFolders == ["Vendor", "**/Generated"])
  }

  @Test("Report discovery settings in imported helpers")
  func importedSettings() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "import Rules",
      "Rules/Settings.swift": """
      import Bylaws
      RuleDiscovery(excluding: ["Vendor"])
      """,
    ])
    let sourcePath = project.fileURL(for: "Rules/Settings.swift").path
    let modules = try PackageModuleIndex(modules: [
      .init(name: "Rules", sourceFiles: [sourcePath], dependencies: ["Bylaws"]),
    ])

    let program = await RuleProgram.discovered(
      atRoot: LexicalFilePath(project.rootURL.path),
      parseCachePolicy: .disabled,
      packageModuleIndex: modules
    )

    #expect(program.errors.map(\.message) == [
      "RuleDiscovery must be declared in the root Bylaws.swift",
    ])
    #expect(program.errors.first?.location.filePath == sourcePath)
  }

  @Test("Report discovery closure arguments")
  func trailingClosure() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: []) {}",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)

    #expect(program.errors
      .map(\.message) == ["RuleDiscovery takes no trailing closure"])
  }
}
