import BylawsCore
import BylawsRunner
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Formatting corrections")
struct FormattingFixTests {
  @Test("Apply source layouts and leave verification unchanged", arguments: [
    FormattingRule.Layout.statements, .properties, .calls, .all,
  ])
  func layouts(layout: FormattingRule.Layout) async throws {
    let (original, expected) = switch layout {
    case .statements:
      (FormattingMock.statements, FormattingMock.spacedStatements)
    case .properties:
      (FormattingMock.properties, FormattingMock.groupedProperties)
    case .calls:
      (FormattingMock.call, FormattingMock.multilineCall)
    case .all:
      (FormattingMock.combined, FormattingMock.formattedCombined)
    }
    try await expectCorrection(original, expected: expected, layout: layout)
  }

  @Test("Wrap calls only above character limit", arguments: [-1, 0, 1])
  func lineLength(delta: Int) async throws {
    let source = "func run() {\n  log(\"👋\", category: \"Navigation\")\n}\n"
    let lineLength = try #require(source.split(separator: "\n").dropFirst()
      .first)
      .count
    let expected = delta < 0 ? """
    func run() {
      log(
        "👋",
        category: "Navigation"
      )
    }

    """ : source
    try await expectCorrection(
      source, expected: expected, layout: .calls,
      maximumLineLength: lineLength + delta
    )
  }

  @Test("Spacing preserves comments strings and existing blank lines")
  func statementTrivia() async throws {
    let original = #"""
    func run() throws {
      let text = "try call(); let value = 1"
      // Keep this comment with the call.
      print(text)

      try save()

      print("done")
      print("again")
    }
    """# + "\n"
    let expected = #"""
    func run() throws {
      let text = "try call(); let value = 1"

      // Keep this comment with the call.
      print(text)

      try save()

      print("done")
      print("again")
    }
    """# + "\n"
    try await expectCorrection(
      original,
      expected: expected,
      layout: .statements
    )
  }

  @Test("Spacing retains Windows line endings")
  func windowsLineEndings() async throws {
    try await expectCorrection(
      "func run() {\r\n  let value = 1\r\n  print(value)\r\n}\r\n",
      expected: "func run() {\r\n  let value = 1\r\n\r\n  print(value)\r\n}\r\n",
      layout: .statements
    )
  }

  @Test("Call wrapping retains line endings", arguments: ["\n", "\r\n"])
  func callLineEndings(newline: String) async throws {
    try await expectCorrection(
      FormattingMock.call.replacing("\n", with: newline),
      expected: FormattingMock.multilineCall.replacing("\n", with: newline),
      layout: .calls
    )
  }

  @Test("Call formatting reads nested closure calls", arguments: [false, true])
  func nestedCalls(formatsOuter: Bool) async throws {
    let outer = formatsOuter ? "register(first: 1, second: 2)" : "register"
    let formattedOuter = formatsOuter ? """
    register(
        first: 1,
        second: 2
      )
    """ : "register"
    let source = """
    func run() {
      \(outer) {
        log("saved", category: "Storage")
      }
    }

    """
    let expected = """
    func run() {
      \(formattedOuter) {
        log(
          "saved",
          category: "Storage"
        )
      }
    }

    """
    try await expectCorrection(source, expected: expected, layout: .calls)
  }

  @Test("Call wrapping preserves try await and trailing closure")
  func effectfulCall() async throws {
    let source = """
    func run() async throws {
      try await load(id: 1, policy: .cached) { use($0) }
    }

    """
    let expected = """
    func run() async throws {
      try await load(
        id: 1,
        policy: .cached
      ) { use($0) }
    }

    """
    try await expectCorrection(source, expected: expected, layout: .calls)
  }

  @Test("Call with argument comment stays unchanged")
  func callComment() async throws {
    let source = "func run() {\n  save(value: 1, /* Keep this explanation. */ to: cache)\n}\n"
    try await expectCorrection(source, expected: source, layout: .calls)
  }

  @Test("Property groups preserve comments and stop at computed member")
  func propertyBoundaries() async throws {
    let source = #"""
    struct ReaderPanel {
      let onClose: () -> Void
      // Query for this panel.
      @State private var query = ""
      @Environment(\.locale) private var locale
      var title: String { "Search" }
      @State private var isExpanded = false
      @Environment(\.isEnabled) private var isEnabled
    }
    """# + "\n"
    let expected = #"""
    struct ReaderPanel {
      @Environment(\.locale) private var locale

      // Query for this panel.
      @State private var query = ""

      let onClose: () -> Void
      var title: String { "Search" }
      @Environment(\.isEnabled) private var isEnabled

      @State private var isExpanded = false
    }
    """# + "\n"
    try await expectCorrection(source, expected: expected, layout: .properties)
  }

  private func expectCorrection(
    _ source: String,
    expected: String,
    layout: FormattingRule.Layout,
    maximumLineLength: Int? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws {
    let project = try TemporaryProject(files: ["Source.swift": source])
    let collector = SourceCapture.Collector()
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["*.swift"],
      swiftLanguageMode: .v6
    )
    let violations = try await SourceCapture.$collector.withValue(collector) {
      try await FormattingRule.violations(
        in: codebase, layout: layout, maximumLineLength: maximumLineLength
      )
    }
    #expect(
      violations.count == (source == expected ? 0 : 1),
      sourceLocation: sourceLocation
    )
    let report = RuleReport(
      id: "formatting", name: "Source follows layout", enforcement: .enforced,
      hint: nil, location: .start(of: project.rootURL.path),
      violations: violations.erased(), warnings: []
    )
    let plan = CorrectionPlan.prepare(
      reports: [report],
      rootPath: project.rootURL.path
    )
    try #require(
      plan.diagnostics.isEmpty,
      "\(plan.diagnostics)",
      sourceLocation: sourceLocation
    )
    let sourceURL = project.fileURL(for: "Source.swift")
    #expect(
      try String(contentsOf: sourceURL, encoding: .utf8) == source,
      sourceLocation: sourceLocation
    )
    _ = try await plan.apply(captures: await collector.captured)
    #expect(
      try String(contentsOf: sourceURL, encoding: .utf8) == expected,
      sourceLocation: sourceLocation
    )
    let verification = try await FormattingRule.violations(
      in: codebase, layout: layout, maximumLineLength: maximumLineLength
    )
    #expect(verification.isEmpty, sourceLocation: sourceLocation)
  }
}
