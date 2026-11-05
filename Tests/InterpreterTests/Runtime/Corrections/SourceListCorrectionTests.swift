import Bylaws
import BylawsCore
import BylawsInterpreter
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite("Portable source list corrections")
struct SourceListCorrectionTests {
  @Test("Native and portable extension modifiers retain members")
  func extensionModifiers() async throws {
    let project = try rulesProject(
      rules: """
      Rule("extension-access") {
        try await app.extensions.violations("Hide extension members") { declaration in
          try Insert("private", into: declaration.modifierList)
        }
      }
      """,
      sources: ["Sources/Extension.swift": "extension Store { func save() {} }"]
    )
    let app = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"]
    )
    let declaration = try #require(await app.extensions.first)
    let correction = try Insert("private", into: declaration.modifierList)
      .correction
    let fix = try #require(correction.fix)
    let expected = "private extension Store { func save() {} }"

    #expect(try declaration.source.file.replacement(applying: fix.edits)
      .replacement == expected)
    #expect(try await correctedSource(in: project) == expected)
  }

  @Test(
    "Native and portable rules combine list methods with builder operations"
  )
  func mixedOperations() async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Replace old arguments") { call in
          let arguments = try call.argumentList
          for argument in arguments {
            if argument.label == "old" {
              try arguments.removing(argument)
              try Insert("new: 1", into: arguments, at: .start)
              try Layout(arguments) {
                Newline()
                Lines { arguments }
                Newline()
              }
            }
          }
        }
      }
      """,
      sources: [
        "Sources/Call.swift": "let result = send(old: 0, keep: nested())",
      ]
    )
    let program = try await loadedProgram(in: project)
    let portable = try await #require(program.rules.first).findings().violations
    let app = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let native = try await app.calls
      .violations("Replace old arguments") { call in
        let arguments = try call.argumentList
        for argument in arguments {
          if argument.label == "old" {
            try arguments.removing(argument)
            try Insert("new: 1", into: arguments, at: .start)
            try Layout(arguments) {
              Newline()
              Lines { arguments }
              Newline()
            }
          }
        }
      }
    let fix = try #require(native.fixes.compactMap(\.self).first)
    let file = try #require(fix.edits.first).source.file
    let expected = "let result = send(\n  new: 1,\n  keep: nested()\n)"

    #expect(native.fixes == portable.fixes)
    #expect(try file.replacement(
      applying: fix.edits,
      layoutCandidates: fix.layoutCandidates
    ).replacement == expected)
    #expect(try await correctedSource(in: project) == expected)
  }

  @Test("Insert arguments at captured positions", arguments: [
    ("send()", ".end", "send(value: 1)"),
    ("send(a: 0)", ".start", "send(value: 1, a: 0)"),
    ("send(a: 0, b: 2)", ".index(1)", "send(a: 0, value: 1, b: 2)"),
    ("send(a: 0)", "SourceListPosition.end", "send(a: 0, value: 1)"),
    ("send {}", ".end", "send(value: 1) {}"),
  ])
  func insertArguments(
    source: String,
    position: String,
    expected: String
  ) async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Pass value") { call in
          try Insert("value: 1", into: call.argumentList, at: \(position))
        }
      }
      """,
      sources: ["Sources/Call.swift": "let result = " + source]
    )
    #expect(try await correctedSource(in: project) == "let result = " +
      expected)
  }

  @Test("Insert into empty declaration lists", arguments: [
    ("modifierList", "final", "final class Model {}"),
    ("attributeList", "@MainActor", "@MainActor class Model {}"),
  ])
  func insertDeclaration(
    list: String,
    text: String,
    expected: String
  ) async throws {
    let project = try rulesProject(
      rules: """
      Rule("declarations") {
        try await app.classes.violations(of: .isFinal).withFix { context in
          try Insert("\(text)", into: context.offender.\(list))
        }
      }
      """,
      sources: ["Sources/Call.swift": "class Model {}"]
    )
    #expect(try await correctedSource(in: project) == expected)
  }

  @Test("Remove arguments with their labels and commas", arguments: [
    ("send(old: 1, keep: 2)", "send(keep: 2)"),
    ("send(old: 1)", "send()"),
  ])
  func removeArguments(source: String, expected: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Remove old arguments") { call in
          let arguments = try call.argumentList
          for argument in arguments {
            if argument.label == "old" { try Remove(argument) }
          }
        }
      }
      """,
      sources: ["Sources/Call.swift": "let result = " + source]
    )
    #expect(try await correctedSource(in: project) == "let result = " +
      expected)
  }

  @Test("List methods preserve owner and collection access", arguments: [
    "try arguments.inserting(\"value: 1\", at: .index(arguments.endIndex))",
    "try arguments.removing(arguments[arguments.startIndex])",
    "try arguments[0].removal()",
  ])
  func listMethods(operation: String) async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Update arguments") { call in
          let arguments = try call.argumentList
          if arguments.count == 1 && arguments.first?.label == "old" {
            \(operation)
          }
        }
      }
      """,
      sources: ["Sources/Call.swift": "let result = send(old: 0)"]
    )
    let expected = operation
      .contains("inserting") ? "send(old: 0, value: 1)" : "send()"
    #expect(try await correctedSource(in: project) == "let result = " +
      expected)
  }

  @Test("List corrections retain comment failures")
  func commentFailure() async throws {
    let project = try rulesProject(
      rules: """
      Rule("arguments") {
        try await app.calls.violations("Pass value") { call in
          try Insert("value: 1", into: call.argumentList)
        }
      }
      """,
      sources: ["Sources/Call.swift": "let result = send(/* keep */)"]
    )
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    #expect(findings.violations.count == 1)
    #expect(findings.violations.fixes == [nil])
  }

  private func correctedSource(in project: TemporaryProject) async throws
    -> String
  {
    let program = try await loadedProgram(in: project)
    let findings = try await #require(program.rules.first).findings()
    let fix = try #require(findings.violations.fixes.compactMap(\.self).first)
    let file = try #require(fix.edits.first).source.file
    return try file.replacement(applying: fix.edits).replacement
  }
}
