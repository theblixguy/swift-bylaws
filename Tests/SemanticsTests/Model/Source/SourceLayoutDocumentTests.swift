import Testing
@testable import BylawsSemantics

@Suite("Composed layout documents")
struct SourceLayoutDocumentTests {
  enum ProposalOrder: CaseIterable {
    case outerFirst, innerFirst, outerCandidate
  }

  @Test(
    "Identity outer layout retains following sibling and suffix in nested width",
    arguments: ProposalOrder.allCases, [
      (39, "let r = outer(inner(\n  1,\n  2\n), 3).longSuffix"),
      (40, "let r = outer(inner(1, 2), 3).longSuffix"),
    ]
  )
  func followingSibling(
    order: ProposalOrder, testCase: (maximumWidth: Int, expected: String)
  ) throws {
    let file = try FileCollector.collect(
      source: "let r = outer(inner(1, 2), 3).longSuffix", path: "/App.swift"
    )
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let outerLayout = try outer.arguments.replacement { outer.arguments }
    let innerLayout = try inner.arguments
      .replacement(whenLineExceeds: testCase.maximumWidth) {
        for argument in inner.arguments {
          Newline()
          argument
        }
        Newline()
      }
    let result = switch order {
    case .outerFirst:
      try file.source.replacement(applying: [outerLayout, innerLayout])
    case .innerFirst:
      try file.source.replacement(applying: [innerLayout, outerLayout])
    case .outerCandidate:
      try file.source.replacement(
        applying: [innerLayout], layoutCandidates: [outerLayout]
      )
    }

    #expect(result.replacement == testCase.expected)
  }

  @Test("Nested identity layouts retain all enclosing siblings and suffixes")
  func multipleAncestors() throws {
    let file = try FileCollector.collect(
      source: "let r = wrap(outer(inner(1, 2), 3), 4).longSuffix",
      path: "/App.swift"
    )
    let wrap = try #require(file.calls.first { $0.name == "wrap" })
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let wrapLayout = try wrap.arguments.replacement { wrap.arguments }
    let outerLayout = try outer.arguments.replacement { outer.arguments }
    let innerLayout = try inner.arguments.replacement(whenLineExceeds: 48) {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let result = try file.source.replacement(
      applying: [innerLayout, wrapLayout, outerLayout]
    )

    #expect(result.replacement ==
      "let r = wrap(outer(inner(\n  1,\n  2\n), 3), 4).longSuffix")
  }

  @Test(
    "Nested width includes following sibling content edits",
    arguments: [
      (
        "let r = outer(inner(1, 2), 3).id",
        "longSibling",
        "let r = outer(inner(\n  1,\n  2\n), longSibling).id"
      ),
      (
        "let r = outer(inner(1, 2), longSibling).id",
        "3",
        "let r = outer(inner(1, 2), 3).id"
      ),
    ]
  )
  func siblingContent(source: String, replacement: String, expected: String)
    throws
  {
    let file = try FileCollector.collect(source: source, path: "/App.swift")
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let sibling = try #require(outer.arguments.last)
    let contentEdit = try sibling.expressionSource
      .replacement(with: replacement)
    let outerLayout = try outer.arguments.replacement { outer.arguments }
    let innerLayout = try inner.arguments.replacement(whenLineExceeds: 36) {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let result = try file.source.replacement(
      applying: [outerLayout, contentEdit, innerLayout]
    )

    #expect(result.replacement == expected)
  }

  @Test("Nested width includes raw edit embedded in following sibling layout")
  func siblingEmbeddedEdit() throws {
    let file = try FileCollector.collect(
      source: "let r = outer(inner(1, 2), send(3)).id", path: "/App.swift"
    )
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let send = try #require(file.calls.first { $0.name == "send" })
    let argument = try #require(send.arguments.first)
    let contentEdit = try argument.expressionSource
      .replacement(with: "longSibling")
    let siblingLayout = try send.arguments.replacement { contentEdit }
    let innerLayout = try inner.arguments.replacement(whenLineExceeds: 38) {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    try #require(innerLayout.source.text == innerLayout.replacement)
    let result = try file.source.replacement(
      applying: [siblingLayout], layoutCandidates: [innerLayout]
    )

    #expect(result.replacement ==
      "let r = outer(inner(\n  1,\n  2\n), send(longSibling)).id")
  }

  @Test(
    "Nested width stops before following physical line",
    arguments: ["\n", "\r\n", "\r"]
  )
  func followingLine(ending: String) throws {
    let source = "let r = outer(inner(1, 2), 3)\(ending)let followingDeclarationHasLongName = 100"
    let file = try FileCollector.collect(source: source, path: "/App.swift")
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let outerLayout = try outer.arguments.replacement { outer.arguments }
    let innerLayout = try inner.arguments.replacement(whenLineExceeds: 29) {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let result = try file.source.replacement(
      applying: [outerLayout, innerLayout]
    )

    #expect(result.replacement.utf8.elementsEqual(source.utf8))
  }

  @Test(
    "Dormant nested layouts retain indentation and line ending bytes",
    arguments: ["\n", "\r\n", "\r"], ["  ", "\t"]
  )
  func dormantBytes(ending: String, indentation: String) throws {
    let source = [
      "func run() {",
      "\(indentation)let r = outer(",
      "\(indentation)\(indentation)inner(1, 2),",
      "\(indentation)\(indentation)3",
      "\(indentation))",
      "}",
    ].joined(separator: ending)
    let file = try FileCollector.collect(source: source, path: "/App.swift")
    let outer = try #require(file.calls.first { $0.name == "outer" })
    let inner = try #require(file.calls.first { $0.name == "inner" })
    let outerLayout = try outer.arguments.replacement(whenLineExceeds: 100) {
      outer.arguments
    }
    let innerLayout = try inner.arguments.replacement(whenLineExceeds: 100) {
      for argument in inner.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let result = try file.source.replacement(
      applying: [innerLayout], layoutCandidates: [outerLayout]
    )

    #expect(result.replacement.utf8.elementsEqual(source.utf8))
  }

  @Test(
    "Wrapping measures commas with their elements at exact width",
    arguments: [
      (11, "send(1,\n  222, 3)"),
      (12, "send(1, 222,\n  3)"),
    ]
  )
  func elementSeparator(width: Int, expected: String) throws {
    let file = try FileCollector.collect(
      source: "send(1, 222, 3)", path: "/App.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let layout = try call.arguments.replacement {
      Wrap(width: width) { call.arguments }
    }
    let result = try file.source.replacement(applying: [layout])

    #expect(result.replacement == expected)
  }

  @Test(
    "Nested conditional layout retains configured tab width",
    arguments: [
      (4, "a\t(1, 2)"),
      (8, "a\t(\n  1,\n  2\n)"),
    ]
  )
  func nestedTabWidth(tabWidth: Int, expected: String) throws {
    let file = try FileCollector.collect(
      source: "a\t(1, 2)", path: "/App.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let layout = try call.arguments.replacement(whenLineExceeds: 10) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let source = try file.source
    let session = SourceLayoutComposition.Session(snapshot: source.snapshot)
    let content = try session.prepareContent(source, applying: [layout])
    let document = SourceLayoutDocument(events: [.content(content)])
    let result = try SourceLayoutRenderer.render(
      document, context: .init(tabWidth: tabWidth)
    )

    #expect(result == expected)
  }

  @Test("Continuation retains line boundary between document segments")
  func continuationLineBoundary() {
    let following = SourceLayoutContinuation.events(
      [.lineBoundary][...], .init(text: "suffix")
    )

    #expect(following.firstLine() == "")
  }

  @Test("Continuation retains space between document segments")
  func continuationSpace() {
    let following = SourceLayoutContinuation.events(
      [.text("one"), .boundary(.soft)][...], .init(text: "two")
    )

    #expect(following.firstLine() == "one two")
  }

  @Test("Render scope drops trailing space before source-owned suffix")
  func scopeTrailingSpace() {
    let following = SourceLayoutContinuation.scope(
      [.text("one"), .boundary(.soft)][...], .init(text: "two")
    )

    #expect(following.firstLine() == "onetwo")
  }

  @Test("Empty render scope retains preceding line boundary")
  func emptyScopeLineBoundary() {
    let following = SourceLayoutContinuation.events(
      [.lineBoundary][...], .scope([], .init(text: "suffix"))
    )

    #expect(following.firstLine() == "")
  }

  @Test("Empty render scope retains preceding space")
  func emptyScopeSpace() {
    let following = SourceLayoutContinuation.events(
      [.text("one"), .boundary(.soft)][...],
      .scope([], .init(text: "two"))
    )

    #expect(following.firstLine() == "one two")
  }

  @Test("Line uses configured tab stops before nested width check")
  func lineTabPlacement() throws {
    let arguments = try preparedArguments(whenLineExceeds: 20)
    let document = SourceLayoutDocument(events: [.line([
      .text("abcdefgh"), .boundary(.soft), .text("\t🦊"), .boundary(.soft),
      .layout(arguments, originalText: nil), .text(")"),
    ])])
    let result = try SourceLayoutRenderer.render(
      document, context: .init(initialColumn: 1, tabWidth: 4)
    )

    #expect(result == "abcdefgh \t🦊 1, 2)")
  }

  @Test("Line rejects nested wrapping after wider tab stops")
  func lineTabWrapping() throws {
    let arguments = try preparedArguments(whenLineExceeds: 20)
    let document = SourceLayoutDocument(events: [.line([
      .text("abcdefgh"), .boundary(.soft), .text("\t🦊"), .boundary(.soft),
      .layout(arguments, originalText: nil), .text(")"),
    ])])

    #expect(throws: SourceLayoutError.lineContainsNewline) {
      try SourceLayoutRenderer.render(
        document, context: .init(initialColumn: 1, tabWidth: 8)
      )
    }
  }

  private func preparedArguments(whenLineExceeds maximumWidth: Int) throws
    -> SourceLayoutPrepared
  {
    let file = try FileCollector.collect(
      source: "send(1, 2)", path: "/App.swift"
    )
    let call = try #require(file.syntaxNodes(of: .functionCall).first?.call)
    let layout = try call.arguments.replacement(whenLineExceeds: maximumWidth) {
      for argument in call.arguments {
        Newline()
        argument
      }
      Newline()
    }
    let source = try file.source
    return try SourceLayoutComposition.Session(snapshot: source.snapshot)
      .prepare(layout)
  }
}
