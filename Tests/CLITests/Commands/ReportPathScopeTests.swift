import BylawsCore
import BylawsSemantics
import Testing
@testable import BylawsRunner

@Suite("Report path scoping")
struct ReportPathScopeTests {
  @Test("A folder finding stays in scope when it is reported at the rule")
  func affectedFolder() {
    let report = Self.report(offenders: [Offender(
      description: "missing folder 'Sources/App/Views'",
      name: "Sources/App/Views",
      location: Self.location(inFile: "Bylaws.swift"),
      affectedPath: "/project/Sources/App/Views"
    )], warnings: [])
    let scoped = report.scoped(to: ReportPathScope(
      paths: ["Sources/App"],
      rootPath: root
    ))
    #expect(scoped.violations.offenders.map(\.name) == ["Sources/App/Views"])
  }

  @Test("A relative path keeps only that file's offenders")
  func relativePathKeepsItsOwnFile() {
    let scoped = Self.report.scoped(
      to: ReportPathScope(paths: ["Sources/App/App.swift"], rootPath: root)
    )

    #expect(scoped.violations.offenders.map(\.name) == ["App"])
    #expect(scoped.warnings.map(\.message) == ["App is unreadable"])
  }

  @Test("An absolute path inside the root keeps the same offenders")
  func absolutePathMatchesRelativePath() {
    let scoped = Self.report.scoped(
      to: ReportPathScope(
        paths: ["\(root)/Sources/App/App.swift"],
        rootPath: root
      )
    )

    #expect(scoped.violations.offenders.map(\.name) == ["App"])
  }

  @Test("A directory keeps every offender below it")
  func directoryKeepsItsDescendants() {
    let scoped = Self.report.scoped(
      to: ReportPathScope(paths: ["Sources"], rootPath: root)
    )

    #expect(scoped.violations.offenders.map(\.name) == ["App", "Model"])
    #expect(scoped.warnings.count == 2)
  }

  @Test("A path outside the root keeps nothing")
  func outsidePathKeepsNothing() {
    let scoped = Self.report.scoped(
      to: ReportPathScope(paths: ["/elsewhere"], rootPath: root)
    )

    #expect(scoped.violations.offenders.isEmpty)
    #expect(scoped.warnings.isEmpty)
  }

  @Test("Scoping keeps the count of what the rule checked")
  func scopingKeepsTheCheckedCount() {
    let scoped = Self.report.scoped(
      to: ReportPathScope(paths: ["/elsewhere"], rootPath: root)
    )

    #expect(scoped.violations.checkedCount == 3)
  }

  @Test("A backslash in a file name is part of the name")
  func backslashIsNotASeparator() {
    let report = Self.report(
      offenders: [Self.offender(named: "Odd", inFile: "Sources/a\\b.swift")],
      warnings: []
    )

    let scoped = report.scoped(
      to: ReportPathScope(paths: ["Sources/a\\b.swift"], rootPath: root)
    )

    #expect(scoped.violations.offenders.map(\.name) == ["Odd"])
  }

  private let root = "/project"

  private static func offender(
    named name: String,
    inFile path: String
  ) -> Offender {
    Offender(
      description: name,
      name: name,
      location: location(inFile: path)
    )
  }

  private static func location(inFile path: String) -> DeclarationLocation {
    DeclarationLocation(
      filePath: "/project/\(path)",
      line: 1,
      column: 1,
      utf8Offset: 0
    )
  }

  private static func report(
    offenders: [Offender],
    warnings: [Rule.Warning]
  ) -> RuleReport {
    RuleReport(
      id: "scoped",
      name: "Offenders stay in scope",
      enforcement: .enforced,
      hint: nil,
      location: location(inFile: "Bylaws.swift"),
      violations: Violations(
        rule: "stay in scope",
        offenders: offenders,
        checkedCount: 3
      ),
      warnings: warnings
    )
  }

  private static let report = report(
    offenders: [
      offender(named: "App", inFile: "Sources/App/App.swift"),
      offender(named: "Model", inFile: "Sources/Model/Model.swift"),
      offender(named: "Suite", inFile: "Tests/AppTests/Suite.swift"),
    ],
    warnings: [
      Rule.Warning(
        message: "App is unreadable",
        location: location(inFile: "Sources/App/App.swift")
      ),
      Rule.Warning(
        message: "Model is unreadable",
        location: location(inFile: "Sources/Model/Model.swift")
      ),
    ]
  )
}
