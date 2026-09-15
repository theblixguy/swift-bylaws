import BylawsCore
import BylawsInterpreter
import BylawsTestSupport
import Foundation
import Testing

@Suite("Security cookbook rules")
struct SecurityCookbookTests {
  @Test(
    "Compiled and interpreted security rules report same violations",
    arguments: [
      (index: 0, count: 1), (index: 1, count: 2), (index: 2, count: 1),
      (index: 3, count: 2), (index: 4, count: 2), (index: 5, count: 6),
      (index: 6, count: 2),
    ]
  )
  func parity(index: Int, count: Int) async throws {
    let rulesFile = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Support/PortableSecurityRules.swift")
    let source = try String(contentsOf: rulesFile, encoding: .utf8)
    var files = SecuritySourceMock.files
    files["Bylaws.swift"] = source + """

    let codebase = Codebase(including: ["Sources/**"])
    let rules = securityRules(codebase)
    """
    let project = try TemporaryProject(files: files)
    let program = await RuleProgram
      .loaded(fromFiles: [project.rootURL.appending(path: "Bylaws.swift").path])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    try #require(program.rules.count == 7)
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let interpreted = try await program.rules[index].findings()
    let compiled = try await securityRules(codebase)[index].findings()
    #expect(interpreted.violations == compiled.violations)
    #expect(interpreted.violations.count == count)
    #expect(interpreted.warnings.isEmpty)
  }

  @Test("Published security recipes match compiled examples")
  func documentedRules() async throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let article = try String(
      contentsOf: repository
        .appending(path: "Sources/Bylaws/Bylaws.docc/SecurityCookbook.md"),
      encoding: .utf8
    )
    let examples = article.components(separatedBy: "```swift\n")
      .dropFirst().map { $0.components(separatedBy: "```")[0] }
      .filter { $0.hasPrefix("Rule(") }
    try #require(examples.count == 7)
    var files = SecuritySourceMock.files
    files["Bylaws.swift"] = """
    import Bylaws
    let codebase = Codebase(including: ["Sources/**"])
    let rules: [Rule] = [
    \(examples.joined(separator: ",\n"))
    ]
    """
    let project = try TemporaryProject(files: files)
    let program = await RuleProgram
      .loaded(fromFiles: [project.rootURL.appending(path: "Bylaws.swift").path])
    try #require(program.diagnostics.isEmpty, "\(program.diagnostics)")
    try #require(program.rules.count == 7)
    let codebase = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    for (interpreted, compiled) in zip(program.rules, securityRules(codebase)) {
      #expect(try await interpreted.findings().violations == compiled.findings()
        .violations)
    }
  }
}
