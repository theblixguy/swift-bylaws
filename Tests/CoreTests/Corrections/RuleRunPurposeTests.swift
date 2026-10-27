import Bylaws
import BylawsCore
import Testing

@Suite("Rule correction purpose")
struct RuleRunPurposeTests {
  private static let codebase = Codebase(root: .sources([
    "Sources/Models.swift": "class lower {}\nclass UPPER {}",
  ]))

  @Test(
    "Purpose controls fix callbacks without changing offender criteria",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func fixCallbacks(purpose: RuleRunPurpose) async throws {
    let recorder = Recorder()
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    let result = try await RuleRunPurpose.$current.withValue(purpose) {
      try await original.withFix { context in
        await recorder.replacement(for: try context.offender.nameSource)
      }
    }

    #expect(result.checkedCount == 2)
    #expect(result.offenders.map(\.name) == ["lower", "UPPER"])
    #expect(result.layoutCandidates.isEmpty)
    if purpose == .checkOnly {
      #expect(result.fixes == [nil, nil])
      #expect(await recorder.names.isEmpty)
    } else {
      #expect(result.fixes.compactMap(\.self).count == 2)
      #expect(await recorder.names == ["lower", "UPPER"])
    }
  }

  @Test("Direct calls retain fix callbacks after a check-only scope")
  func directCalls() async throws {
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    _ = try await RuleRunPurpose.$current.withValue(.checkOnly) {
      try await original.withFix { _ in }
    }
    let recorder = Recorder()
    let result = try await original.withFix { context in
      await recorder.replacement(for: try context.offender.nameSource)
    }

    #expect(await recorder.names == ["lower", "UPPER"])
    #expect(result.fixes.compactMap(\.self).count == 2)
    #expect(result.fixes.compactMap(\.self).flatMap(\.edits)
      .map(\.replacement) == ["LOWER", "UPPER"])
  }

  @Test(
    "Formatting detectors run in each purpose",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func detectsChanges(purpose: RuleRunPurpose) async throws {
    let recorder = Recorder()
    let result = try await RuleRunPurpose.$current.withValue(purpose) {
      try await Self.codebase.classes.violations("Use uppercase names") {
        declaration in
        await recorder.replacement(for: try declaration.nameSource)
      }
    }

    #expect(await recorder.names == ["lower", "UPPER"])
    #expect(result.checkedCount == 2)
    #expect(result.offenders.map(\.name) == ["lower"])
    if purpose == .checkOnly {
      #expect(result.fixes == [nil])
    } else {
      let fix = try #require(result.fixes.first ?? nil)
      #expect(fix.edits.map(\.replacement) == ["LOWER"])
    }
  }

  @Test(
    "Passing layout context remains available for corrections",
    arguments: [RuleRunPurpose.checkOnly, .proposeCorrections]
  )
  func passingContext(purpose: RuleRunPurpose) async throws {
    let codebase = Codebase(root: .sources([
      "Sources/Model.swift": "@MainActor @Observable\nclass Model {}",
    ]))
    let result = try await RuleRunPurpose.$current.withValue(purpose) {
      try await codebase.classes.violations("Keep attribute order") {
        declaration in
        try declaration.attributes.replacement {
          Line { declaration.attributes }
        }
      }
    }

    #expect(result.checkedCount == 1)
    #expect(result.isEmpty)
    #expect(result.fixes.isEmpty)
    if purpose == .checkOnly {
      #expect(result.layoutCandidates.isEmpty)
    } else {
      let candidate = try #require(result.layoutCandidates.first)
      #expect(result.layoutCandidates.count == 1)
      #expect(candidate.replacement == "@MainActor @Observable\n")
    }
  }

  @Test("Structured child tasks inherit the correction purpose")
  func childTasks() async throws {
    let recorder = Recorder()
    let original = try await Self.codebase.classes.violations(of: .isFinal)
    let count = try await RuleRunPurpose.$current.withValue(.checkOnly) {
      try await withThrowingTaskGroup(of: Int.self) { group in
        group.addTask {
          let result = try await original.withFix { context in
            await recorder.replacement(for: try context.offender.nameSource)
          }
          return result.count
        }
        let first = try await group.next()
        return try #require(first)
      }
    }

    #expect(count == 2)
    #expect(await recorder.names.isEmpty)
  }

  private actor Recorder {
    private(set) var names: [String] = []

    func replacement(for source: SourceSlice) -> SourceFix.Edit {
      names.append(source.text)
      return source.replacement(with: source.text.uppercased())
    }
  }
}
