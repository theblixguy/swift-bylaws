import Bylaws
import BylawsCore
import Foundation
import Testing

@Suite("Typed source corrections")
struct SourceFixTests {
  private static let codebase = Codebase(
    root: .sources([
      "Sources/First.swift": "class First {}",
      "Sources/Second.swift": "class Second {}",
    ]),
    swiftLanguageMode: .v6
  )

  @Test("Correction uses offender source and preserves diagnostic witness")
  func offenderSource() async throws {
    let text = """
    struct Reporter {
      func run() {
        print("done")
      }
    }
    """
    let codebase = Codebase(
      root: .sources(["Sources/Reporter.swift": text]),
      swiftLanguageMode: .v6
    )
    let violations = try await codebase.files
      .violations(matching: .calls("print"))
      .withFix("Mark file") { context in
        let source = try context.source
        source.replacement(with: "// checked\n" + source.text)
      }
    let erased = violations.erased()
    let offender = try #require(erased.offenders.first)
    let fix = try #require(erased.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(offender.location.line == 3)
    #expect(edit.source.range.lowerBound == 0)
    #expect(edit.source.text == text)
    #expect(edit.replacement == "// checked\n" + text)
    #expect(try violations.offenders.first?.source.text == text)
  }

  @Test("Narrowed selection retains cross-file correction context")
  func crossFileContext() async throws {
    let violations = try await Self.codebase.classes.named("First")
      .violations(of: .isFinal)
      .withFix("Update related classes") { context in
        let second = try await context.codebase.classes.named("Second").only()
        try context.source.slice(0..<0).replacement(with: "final ")
        try second.nameSource.replacement(with: "Other")
      }
    let fix = try #require(violations.fixes.first ?? nil)

    #expect(fix.edits.count == 2)
    #expect(fix.edits.map(\.source.filePath) == [
      "/virtual/Sources/First.swift", "/virtual/Sources/Second.swift",
    ])
    #expect(fix.edits.map(\.replacement) == ["final ", "Other"])
    #expect(fix.edits.map(\.source.text) == ["", "Second"])
  }

  @Test("Erasure filtering and combined findings retain paired corrections")
  func propagation() async throws {
    let violations = try await Self.codebase.classes.violations(of: .isFinal)
      .withFix("Add final") { context in
        try context.source.slice(0..<0).replacement(with: "final ")
      }
    let erased = violations.erased()
    let first = erased.filteringOffenders { $0.name == "First" }
    let second = erased.filteringOffenders { $0.name == "Second" }
    let combined = Rule.Findings(checks: [second, first]).violations

    #expect(erased.fixes == violations.fixes)
    #expect(erased.erased().fixes == erased.fixes)
    #expect(first.offenders.map(\.name) == ["First"])
    #expect(second.offenders.map(\.name) == ["Second"])
    #expect(combined.offenders.map(\.name) == ["Second", "First"])
    #expect(combined.fixes == second.fixes + first.fixes)
    #expect(combined.checkedCount == first.checkedCount + second.checkedCount)
    #expect(combined.offenders.allSatisfy { $0.requirement == erased.rule })
    let firstFix = try #require(first.fixes.first ?? nil)
    let secondFix = try #require(second.fixes.first ?? nil)
    #expect(firstFix.edits.first?.source
      .filePath == "/virtual/Sources/First.swift")
    #expect(secondFix.edits.first?.source
      .filePath == "/virtual/Sources/Second.swift")
  }

  @Test("Violation transport preserves materialised corrections")
  func transport() async throws {
    let original = try await Self.codebase.classes.named("First")
      .violations(of: .isFinal)
      .withFix("Add final") { context in
        try context.source.slice(0..<0).replacement(with: "final ")
      }
      .erased()
    let decoded = try JSONDecoder().decode(
      Violations<Offender>.self, from: JSONEncoder().encode(original)
    )

    #expect(decoded == original)
    #expect(decoded.fixes == original.fixes)
    #expect(decoded.filteringOffenders { _ in false }.fixes.isEmpty)
  }

  @Test(
    "Synthetic and decoded offenders reject source corrections",
    arguments: [false, true]
  )
  func unbackedOffenders(decoded: Bool) async throws {
    let file = try FileCollector.collect(
      source: "import Foundation", path: "/virtual/Sources/App.swift"
    )
    let original = try #require(file.imports.first)
    let offender = if decoded {
      try JSONDecoder().decode(
        Import.self, from: JSONEncoder().encode(original)
      )
    } else {
      Import(name: original.name, location: original.location)
    }
    let violations = Violations(
      rule: "use another module", offenders: [offender], checkedCount: 1
    )

    await #expect(throws: SourceError.unavailable) {
      try await violations.withFix { context in
        try context.source.replacement(with: "import Other")
      }
    }
  }

  @Test("Empty builder leaves each offender without a correction")
  func emptyBuilder() async throws {
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    let violations = try await original.withFix { _ in }

    #expect(violations.offenders == original.offenders)
    #expect(violations.checkedCount == original.checkedCount)
    #expect(violations.fixes == [nil, nil])
  }

  @Test("Offender without source provider reports context error")
  func missingSourceProvider() async {
    let violations = Violations(
      rule: "provide source", offenders: [1], checkedCount: 1
    )

    await #expect(throws: FixContextError.sourceUnavailable) {
      try await violations.withFix { context in
        try context.source.replacement(with: "")
      }
    }
  }

  @Test("Manually constructed violations report missing codebase")
  func missingCodebase() async {
    let violations = Violations(
      rule: "provide context", offenders: [1], checkedCount: 1
    )

    await #expect(throws: FixContextError.codebaseUnavailable) {
      try await violations.withFix { context in
        let file = try await context.codebase.files.only()
        try file.source.replacement(with: "")
      }
    }
  }

  @Test("Unchanged replacement retains the authored proposal")
  func unchangedReplacement() async throws {
    let violations = try await Self.codebase.classes.named("First")
      .violations(of: .isFinal)
      .withFix { context in
        let source = try context.source
        source.replacement(with: source.text)
      }
    let fix = try #require(violations.fixes.first ?? nil)
    let edit = try #require(fix.edits.first)

    #expect(edit.source.text == "class First {}")
    #expect(edit.replacement == edit.source.text)
  }

  @Test("Async builder finishes once per offender before returning")
  func asyncBuilder() async throws {
    let recorder = FixRecorder()
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    let violations = try await original.withFix { context in
      await recorder.replacement(for: try context.source)
    }
    let recorded = await recorder.sources

    #expect(recorded == original.offenders.map { "class \($0.name) {}" })
    #expect(violations.fixes.compactMap(\.self).count == original.count)
    _ = violations.erased()
    _ = Rule.Findings(violations: violations.erased()).violations
    #expect(await recorder.sources == recorded)
  }

  @Test("Passing checks leave correction builder uncalled")
  func passingCheck() async throws {
    let recorder = FixRecorder()
    let violations = try await Self.codebase.classes
      .violations(of: Matcher<Class>("be a class") { _ in true })
      .withFix { context in
        await recorder.replacement(for: try context.source)
      }

    #expect(violations.isEmpty)
    #expect(violations.fixes.isEmpty)
    #expect(await recorder.sources.isEmpty)
  }

  @Test("Correction builder errors escape without changing the check")
  func throwingBuilder() async throws {
    let violations = try await Self.codebase.classes.named("First")
      .violations(of: .isFinal)

    await #expect(throws: MockError.stopped) {
      try await violations.withFix { context in
        try failingEdit(for: context.source)
      }
    }
    #expect(violations.count == 1)
    #expect(violations.fixes == [nil])
  }

  private func failingEdit(for source: SourceSlice) throws -> SourceFix.Edit {
    throw MockError.stopped
  }

  private enum MockError: Error, Equatable {
    case stopped
  }

  private actor FixRecorder {
    private(set) var sources: [String] = []

    func replacement(for source: SourceSlice) -> SourceFix.Edit {
      sources.append(source.text)
      return source.replacement(with: "final " + source.text)
    }
  }
}
