import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Rule discovery paths")
struct RuleDiscoveryPathTests {
  @Test(
    "Match complete file names and retain Unicode directories",
    arguments: ["", "/", "/./"]
  )
  func completeNames(rootSuffix: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": """
      let app = Codebase(including: ["Sources/**"])
      Rule("root") { app.classes.violations(of: .isFinal) }
      """,
      "Bylaws.baseline.swift": BaselineFile.render(name: "root", entries: []),
      "Modules/Café/🧪/\u{301}Feature/Bylaws.swift": """
      let feature = Codebase(including: ["Sources/**"])
      Rule("unicode") { feature.classes.violations(of: .isFinal) }
      """,
      "Modules/Café/🧪/\u{301}Feature/Bylaws.baseline.swift": BaselineFile
        .render(
          name: "feature",
          entries: []
        ),
      "Archive/Bylaws.swift/Nested/Bylaws.swift": """
      let archive = Codebase(including: ["Sources/**"])
      Rule("nested") { archive.classes.violations(of: .isFinal) }
      """,
      "Archive/Bylaws.baseline.swift/Nested/Bylaws.baseline.swift": BaselineFile
        .render(name: "archive", entries: []),
      "Wrong/NotBylaws.swift": "cannot parse this",
      "Wrong/Bylaws.swift.bak": "cannot parse this",
      "Wrong/.Bylaws.swift": "cannot parse this",
      "Wrong/\u{301}Bylaws.swift": "cannot parse this",
      "Wrong/NotBylaws.baseline.swift": "cannot parse this",
      "Wrong/Bylaws.baseline.swift.bak": "cannot parse this",
    ])
    let root = project.rootURL.path + rootSuffix

    let program = await RuleProgram.discovered(atRoot: root)
    let baselines = await DiscoveredBaselines.discovered(atRoot: root)

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["root", "nested", "unicode"])
    #expect(program.rules.map(\.location.filePath) == [
      project.fileURL(for: "Bylaws.swift").path,
      project.fileURL(for: "Archive/Bylaws.swift/Nested/Bylaws.swift").path,
      project.fileURL(for: "Modules/Café/🧪/\u{301}Feature/Bylaws.swift").path,
    ])
    #expect(baselines.diagnostics.isEmpty)
    #expect(baselines.baselines.map(\.relativeDirectory) == [
      "", "Archive/Bylaws.baseline.swift/Nested",
      "Modules/Café/🧪/\u{301}Feature",
    ])
  }

  @Test(
    "Skip exact directory names and retain prefix-sharing siblings",
    arguments: [
      ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods",
    ]
  )
  func skippedNames(directory: String) async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [\"Vendor\"])",
      "Bylaws.baseline.swift": BaselineFile.render(name: "root", entries: []),
      "\(directory)/Nested/Bylaws.swift": "cannot parse this",
      "Nested/\(directory)/Bylaws.baseline.swift": "cannot parse this",
      "\(directory)Kit/Bylaws.swift": """
      let sibling = Codebase(including: ["Sources/**"])
      Rule("sibling") { sibling.classes.violations(of: .isFinal) }
      """,
      "Nested/\(directory)Kit/Bylaws.baseline.swift": BaselineFile.render(
        name: "sibling", entries: []
      ),
      "Vendor/Bylaws.swift": "cannot parse this",
      "Vendor/Bylaws.baseline.swift": "cannot parse this",
    ])

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let baselines = await DiscoveredBaselines.discovered(
      atRoot: project.rootURL.path
    )

    #expect(program.diagnostics.isEmpty)
    #expect(program.rules.map(\.id) == ["sibling"])
    #expect(baselines.diagnostics.isEmpty)
    #expect(baselines.baselines.map(\.relativeDirectory) == [
      "", "Nested/\(directory)Kit",
    ])
  }

  @Test(
    "Report unreadable directory paths during rule and baseline discovery",
    .enabled(if: getuid() != 0, "Root can read a directory with mode 000.")
  )
  func unreadableDirectory() async throws {
    let project = try TemporaryProject(files: [
      "Bylaws.swift": "RuleDiscovery(excluding: [])",
      "Modules/Café/Private/Marker.txt": "",
    ])
    let directory = project.fileURL(for: "Modules/Café/Private").path
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: directory
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: directory
      )
    }

    let program = await RuleProgram.discovered(atRoot: project.rootURL.path)
    let baselines = await DiscoveredBaselines.discovered(
      atRoot: project.rootURL.path
    )

    #expect(program.diagnostics.map(\.message) == ["cannot read the directory"])
    #expect(program.diagnostics.map(\.location.filePath) == [directory])
    #expect(baselines.diagnostics
      .map(\.message) == ["cannot read the directory"])
    #expect(baselines.diagnostics.map(\.location.filePath) == [directory])
  }
}
