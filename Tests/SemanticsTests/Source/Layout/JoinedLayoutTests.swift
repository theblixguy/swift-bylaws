import BylawsSemantics
import Foundation
import Testing

@Suite("Joined source layouts")
struct JoinedLayoutTests {
  @Test("Joined arguments form one unit inside Lines", arguments: [false, true])
  func argumentGroup(trailingComma: Bool) throws {
    let comma = trailingComma ? "," : ""
    let file = try collect("send(first, second, option: true\(comma))")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let operation = try Layout(arguments) {
      Lines(boundaries: .newline) {
        Joined(arguments.prefix(2))
        arguments.dropFirst(2)
      }
    }

    #expect(try applying(operation) == """
    send(
      first, second,
      option: true\(comma)
    )
    """)
  }

  @Test("Joined retains intrinsic multiline source and contained corrections")
  func multilineContents() throws {
    let file = try collect("""
    send(nested(
      value: 1
    ), second, values: [2, 3])
    """)
    let call = try #require(file.syntaxNodes(of: .functionCall)
      .compactMap(\.call).first { $0.name == "send" })
    let arguments = call.arguments
    try #require(arguments.count == 3)
    let elements = try #require(arguments[2].expression?.elements)
    let operation = try Layout(arguments) {
      Lines(boundaries: .newline) {
        Joined { arguments.prefix(2) }
        arguments.dropFirst(2)
      }
    }.applying(toEach: [elements]) {
      Lines($0, boundaries: .newline)
    }

    #expect(try applying(operation) == """
    send(
      nested(
        value: 1
      ), second,
      values: [
        2,
        3
      ]
    )
    """)
  }

  @Test("Empty Joined adds no separators or boundary lines")
  func emptyGroup() throws {
    let file = try collect("send(first, second)")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    try #require(arguments.count == 2)
    let empty: [FunctionCall.Argument] = []
    let operation = try Layout(arguments) {
      Lines(boundaries: .newline) {
        Joined(empty)
        Joined { Newline() }
        arguments[0]
        Joined {
          BlankLine()
          Joined {}
        }
        arguments[1]
        Joined(layout: SourceLayout(empty))
      }
    }

    #expect(try applying(operation) == """
    send(
      first,
      second
    )
    """)
  }

  @Test("Stored Joined components retain captured layout through encoding")
  func storedGroup() throws {
    let file = try collect("send(first, second, option: true)")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let joined =
      Joined(layout: Joined(layout: SourceLayout(arguments.prefix(2))))
    let operation = try Layout(arguments, layout: Lines {
      joined
      arguments.dropFirst(2)
    })
    let fix = try #require(operation.correction.fix)
    let restored = try JSONDecoder().decode(
      SourceFix.self, from: JSONEncoder().encode(fix)
    )

    #expect(try applying(restored) == "send(first, second,\n  option: true)")
  }

  @Test("Joined rejects repeated source elements")
  func repeatedSource() throws {
    let file = try collect("send(first, second)")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    let first = try #require(arguments.first)

    #expect(throws: SourceLayoutReplacementError.repeatedElement) {
      try Layout(arguments) {
        Joined(arguments)
        first
      }
    }
  }

  @Test("Joined retains source safety checks", arguments: [
    "send(first, /* Keep */ second)",
    "send(first,\n  // swiftformat:disable\n  second)",
  ])
  func ambiguousTrivia(source: String) throws {
    let file = try collect(source)
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments

    #expect(throws: SourceLayoutReplacementError.ambiguousTrivia) {
      try Layout(arguments, layout: Joined(arguments))
    }
  }

  @Test("Nested Lines and Joined retain explicit spacing controls")
  func nestedControls() throws {
    let file = try collect("send(first, second, third, fourth)")
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let arguments = call.arguments
    try #require(arguments.count == 4)
    let operation = try Layout(arguments) {
      Lines(boundaries: .newline) {
        Joined {
          arguments[0]
          Joined { arguments[1] }
          BlankLine()
          Lines {
            arguments[2]
            arguments[3]
          }
        }
      }
    }

    #expect(try applying(operation) == """
    send(
      first, second,

      third,
      fourth
    )
    """)
  }

  @Test("Joined retains conditional compilation boundaries")
  func conditionalCases() throws {
    let file = try collect("""
    switch value {
    #if DEBUG
    case .first: consume()
    #endif
    case .second: consume()
    }
    """)
    let elements = try #require(file.syntaxNodes(of: .switchCaseList).first)
      .elements

    #expect(throws: SourceLayoutReplacementError.conditionalCompilation) {
      try Layout(elements, layout: Joined(elements))
    }
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Calls.swift")
  }

  private func applying(_ operation: some SourceCorrectionProviding) throws
    -> String
  {
    let fix = try #require(operation.correction.fix)
    let source = try #require(fix.edits.first).source.file
    return try source.replacement(applying: fix.edits).replacement
  }
}
