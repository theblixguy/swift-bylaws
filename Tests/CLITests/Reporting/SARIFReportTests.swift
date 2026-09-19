import BylawsCore
import BylawsInterpreter
import BylawsRunner
import BylawsSemantics
import Foundation
import Testing
@testable import bylaws_cli

@Suite("Rule findings in SARIF output")
struct SARIFReportTests {
  @Test("Violation result points to the offender and rule declaration")
  func violationLocation() throws {
    let run = try Self.run(reports: [
      Self.report(
        id: "viewmodel-inheritance",
        hint: "a view model belongs in Sources/App",
        offenders: [Self.offender]
      ),
    ])

    let results = try Self.objects(run["results"])
    let result = try #require(results.first)
    #expect(result["ruleId"] as? String == "viewmodel-inheritance")
    #expect(result["level"] as? String == "error")
    let message = try Self.object(result["message"])
    #expect(
      message["text"] as? String
        == "class HomeViewModel violates "
        + "'ViewModels inherit from BaseViewModel' "
        + "(a view model belongs in Sources/App)"
    )

    let physical = try Self.firstLocation(of: result)
    let artifact = try Self.object(physical["artifactLocation"])
    #expect(artifact["uri"] as? String == "Sources/Home.swift")
    let region = try Self.object(physical["region"])
    #expect(region["startLine"] as? Int == 7)
    #expect(region["startColumn"] as? Int == 3)

    let relatedLocations = try Self.objects(result["relatedLocations"])
    let ruleLocation = try #require(relatedLocations.first)
    let relatedMessage = try Self.object(ruleLocation["message"])
    #expect(
      relatedMessage["text"] as? String
        == "Rule 'viewmodel-inheritance' is declared here."
    )
    let rulePhysical = try Self.object(ruleLocation["physicalLocation"])
    let ruleArtifact = try Self.object(rulePhysical["artifactLocation"])
    #expect(ruleArtifact["uri"] as? String == "Bylaws.swift")
    let ruleRegion = try Self.object(rulePhysical["region"])
    #expect(ruleRegion["startLine"] as? Int == 4)
    #expect(ruleRegion["startColumn"] as? Int == 1)
  }

  @Test("Path outside project uses file URI")
  func externalPath() throws {
    let run = try Self.run(
      reports: [Self.report(id: "r", offenders: [Self.offender])],
      rootPath: "/elsewhere"
    )

    let results = try Self.objects(run["results"])
    let physical = try Self.firstLocation(of: try #require(results.first))
    let artifact = try Self.object(physical["artifactLocation"])
    #expect(artifact["uri"] as? String == "file:///project/Sources/Home.swift")
  }

  @Test("File URI encodes reserved characters")
  func fileURIEscaping() throws {
    let offender = Offender(
      description: "class HomeViewModel",
      location: DeclarationLocation.start(of: "/project/Space #%.swift")
    )
    let run = try Self.run(
      reports: [Self.report(id: "r", offenders: [offender])],
      rootPath: "/elsewhere"
    )

    let results = try Self.objects(run["results"])
    let physical = try Self.firstLocation(of: try #require(results.first))
    let artifact = try Self.object(physical["artifactLocation"])
    #expect(
      artifact["uri"] as? String
        == "file:///project/Space%20%23%25.swift"
    )
  }

  @Test("Project-relative URI encodes reserved characters")
  func relativeURIEscaping() throws {
    let offender = Offender(
      description: "class HomeViewModel",
      location: DeclarationLocation.start(
        of: "/project/Sources/Space #:%.swift"
      )
    )
    let run = try Self.run(reports: [
      Self.report(id: "r", offenders: [offender]),
    ])

    let results = try Self.objects(run["results"])
    let physical = try Self.firstLocation(of: try #require(results.first))
    let artifact = try Self.object(physical["artifactLocation"])
    #expect(
      artifact["uri"] as? String
        == "Sources/Space%20%23%3A%25.swift"
    )
  }

  @Test("Advisory rule reports at warning level")
  func advisoryLevel() throws {
    let run = try Self.run(reports: [
      Self.report(
        id: "no-print",
        enforcement: .advisory,
        offenders: [Self.offender]
      ),
    ])

    let rules = try Self.rules(of: run)
    let configuration = try Self.object(
      try #require(rules.first)["defaultConfiguration"]
    )
    #expect(configuration["level"] as? String == "warning")

    let results = try Self.objects(run["results"])
    #expect(try #require(results.first)["level"] as? String == "warning")
  }

  @Test("Reports with same rule ID share rule index")
  func sharedRuleIndex() throws {
    let run = try Self.run(reports: [
      Self.report(id: "viewmodel-inheritance", offenders: [Self.offender]),
      Self.report(id: "viewmodel-inheritance", offenders: [Self.offender]),
      Self.report(id: "no-print", offenders: [Self.offender]),
    ])

    let rules = try Self.rules(of: run)
    #expect(rules.map { $0["id"] as? String } == [
      "viewmodel-inheritance", "no-print",
    ])

    let results = try Self.objects(run["results"])
    #expect(results.map { $0["ruleIndex"] as? Int } == [0, 0, 1])
  }

  @Test("Empty query reports warning message")
  func emptyQuery() throws {
    let run = try Self.run(reports: [
      Self.report(id: "r", offenders: [], checkedCount: 0),
    ])

    let results = try Self.objects(run["results"])
    let message = try Self.object(try #require(results.first)["message"])
    #expect(
      message["text"] as? String
        == "ViewModels inherit from BaseViewModel: the query matched no declarations"
    )
  }

  @Test("Run without diagnostics reports successful invocation")
  func successfulInvocation() throws {
    let run = try Self.run(reports: [
      Self.report(id: "r", offenders: [Self.offender]),
    ])

    let invocations = try Self.objects(run["invocations"])
    let invocation = try #require(invocations.first)
    #expect(invocation["executionSuccessful"] as? Bool == true)
    #expect(
      (invocation["toolExecutionNotifications"] as? [[String: Any]])?.isEmpty
        == true
    )
  }

  private static let root = "/project"

  private static func report(
    id: Rule.ID,
    enforcement: Enforcement = .enforced,
    hint: String? = nil,
    offenders: [Offender],
    checkedCount: Int = 1,
    warnings: [Rule.Warning] = []
  ) -> RuleReport {
    RuleReport(
      id: id,
      name: "ViewModels inherit from BaseViewModel",
      enforcement: enforcement,
      hint: hint,
      location: DeclarationLocation(
        filePath: "\(root)/Bylaws.swift",
        line: 4,
        column: 1,
        utf8Offset: 20
      ),
      violations: Violations(
        rule: "inherit from BaseViewModel",
        offenders: offenders,
        checkedCount: checkedCount
      ),
      warnings: warnings
    )
  }

  private static let offender = Offender(
    description: "class HomeViewModel",
    name: "HomeViewModel",
    location: DeclarationLocation(
      filePath: "\(root)/Sources/Home.swift",
      line: 7,
      column: 3,
      utf8Offset: 42
    )
  )

  private static func object(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
  }

  private static func objects(_ value: Any?) throws -> [[String: Any]] {
    try #require(value as? [[String: Any]])
  }

  private static func run(
    reports: [RuleReport],
    diagnostics: [Diagnostic] = [],
    rootPath: String = root
  ) throws -> [String: Any] {
    let output = try render(
      reports: reports,
      diagnostics: diagnostics,
      format: .sarif,
      quiet: true,
      rootPath: rootPath
    )
    let log = try object(JSONSerialization.jsonObject(with: Data(output.utf8)))
    #expect(log["version"] as? String == "2.1.0")
    let runs = try objects(log["runs"])
    return try #require(runs.first)
  }

  private static func firstLocation(
    of result: [String: Any]
  ) throws -> [String: Any] {
    let locations = try objects(result["locations"])
    let location = try #require(locations.first)
    return try object(location["physicalLocation"])
  }

  private static func rules(of run: [String: Any]) throws -> [[String: Any]] {
    let tool = try object(run["tool"])
    let driver = try object(tool["driver"])
    return try objects(driver["rules"])
  }
}
