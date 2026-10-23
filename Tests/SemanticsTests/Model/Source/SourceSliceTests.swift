import BylawsSemantics
import BylawsSyntax
import Foundation
import Testing

@Suite("Source slices and correction provenance")
struct SourceSliceTests {
  @Test("File reads preserve BOM and UTF-8 source positions")
  func byteOrderMark() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("bylaws-bom-\(UUID().uuidString).swift")
    defer { try? FileManager.default.removeItem(at: path) }
    let bytes = Data("\u{FEFF}let café = 0xff\r\n".utf8)
    try bytes.write(to: path)
    let file = try FileCollector.collect(fileAt: path.path)
    #expect(try Data(file.source.text.utf8) == bytes)
    let literal = try #require(file.syntaxNodes(of: .integerLiteral).first)
    let slice = try literal.source
    #expect(Array(bytes[slice.range]) == Array("0xff".utf8))
  }

  @Test("Declarations retain exact source and identifiers")
  func declarationProjections() throws {
    let file = try FileCollector.collect(
      source: """
      import Foundation
      struct `Store` {
        var first = 1, second = 2
        func `read`() { print(first) }
        init() { first = 3 }
      }
      extension Store {}
      typealias Name = String
      """, path: "/virtual/Store.swift"
    )
    let store = try #require(file.structs.first)
    let function = try #require(file.functions.first)
    let initializer = try #require(file.initializers.first)
    #expect(try store.nameSource.text == "`Store`")
    #expect(try function.nameSource.text == "`read`")
    #expect(try function.bodySource.text == " print(first) ")
    #expect(try initializer.bodySource.text == " first = 3 ")
    #expect(try file.properties[1].source.text == "second = 2")
    #expect(try file.imports[0].source.text == "import Foundation")
    #expect(try file.extensions[0].source.text == "extension Store {}")
    #expect(try file.typealiases[0].nameSource.text == "Name")
    #expect(try store.source.file.text == file.sourceText)
  }

  @Test("Body projections exclude braces and retain interior trivia")
  func bodyContents() throws {
    let file = try FileCollector.collect(
      source: """
      struct Store {
        var value: Int { get { 1 } }
        func empty() {}
      }
      protocol Reader { func read() }
      extension Store { func extra() {} }
      """, path: "/virtual/Bodies.swift"
    )
    #expect(try file.structs[0].bodySource.text.hasPrefix("\n  var value"))
    #expect(try file.structs[0].bodySource.text.hasSuffix("\n"))
    #expect(try file.properties[0].bodySource.text == " get { 1 } ")
    #expect(try file.functions[0].bodySource.text.isEmpty)
    #expect(try file.protocols[0].bodySource.text == " func read() ")
    #expect(try file.extensions[0].bodySource.text == " func extra() {} ")
    #expect(throws: SourceError.missingPart) {
      _ = try file.protocols[0].requiredFunctions[0].bodySource
    }
  }

  @Test("Call projections distinguish receiver and repeated arguments")
  func callProjections() throws {
    let file = try FileCollector.collect(
      source: "let result = store.`save`(first: 1, second: 1)",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls.first)
    let first = try call.argument(labeled: "first")
    let second = try call.argument(labeled: "second")
    #expect(try call.memberNameSource.text == "`save`")
    #expect(try call.calledExpressionSource.text == "store.`save`")
    #expect(try call.source.text == "store.`save`(first: 1, second: 1)")
    #expect(try first.labelSource?.text == "first")
    #expect(try first.expressionSource.text == "1")
    #expect(try first.source.range != second.source.range)
    let expression = try #require(second.expression)
    #expect(try expression.source.range == second.source.range)
    #expect(try expression.source.file.text == file.sourceText)
  }

  @Test("Nested expression and assignment projections retain original file")
  func nestedProjections() throws {
    let file = try FileCollector.collect(
      source: "func run() { target = first + second; use(label: 1) }",
      path: "/virtual/App.swift"
    )
    let assignment = try #require(file.assignments.first)
    #expect(try assignment.source.text == "target = first + second")
    #expect(try assignment.value.source.text == "first + second")
    #expect(try assignment.value.source.file.text == file.sourceText)
    let expression = try #require(file.expressions.first {
      $0.calledExpression?.text == "use"
    })
    let argument = try #require(expression.arguments?.first)
    #expect(try argument.labelSource?.text == "label")
    #expect(try argument.expressionSource.text == "1")
    #expect(try argument.source.file.text == file.sourceText)
    let bindingFile = try FileCollector.collect(
      source: "func use() { let local = 1 }", path: "/virtual/Binding.swift"
    )
    let binding = try #require(bindingFile.variableBindings.first)
    #expect(try binding.source.text == "local = 1")
    #expect(try binding.nameSource.text == "local")
  }

  @Test("Call identifiers retain force-unwrapped syntax", arguments: [
    "factory!()", "factory<Int>!()",
  ])
  func unwrappedCallee(_ callText: String) throws {
    let file = try FileCollector.collect(
      source: "let result = \(callText)", path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls.first)
    #expect(try call.memberNameSource.text == "factory")
    #expect(try call.memberNameSource.replacement(with: "make").source
      .text == "factory")
  }

  @Test("Unnamed callees report missing source part")
  func unnamedCallee() throws {
    let file = try FileCollector.collect(
      source: "let value = ({ 1 })()", path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls.first)
    #expect(try call.calledExpressionSource.text == "({ 1 })")
    #expect(throws: SourceError.missingPart) { _ = try call.memberNameSource }
  }

  @Test(
    "Argument lookup rejects missing and repeated labels",
    arguments: ["missing", "value"]
  )
  func argumentCardinality(_ label: String) throws {
    let file = try FileCollector.collect(
      source: "func check() { run(value: 1, value: 2) }",
      path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls.first)
    #expect(throws: SourceError.self) { try call.argument(labeled: label) }
  }

  @Test("Regex matches preserve UTF-8 offsets and repeated text")
  func regexOffsets() throws {
    let file = try FileCollector.collect(
      source: "let café = [\"🦊\", \"🦊\"]\r\n", path: "/virtual/Unicode.swift"
    )
    let whole = try file.source
    let matches = whole.matches(of: /🦊/)
    #expect(matches.count == 2)
    #expect(matches.map(\.text) == ["🦊", "🦊"])
    #expect(matches[0].range.count == 4)
    #expect(matches[0].range.lowerBound < matches[1].range.lowerBound)
    #expect(try whole.matches(of: /café/).only().text == "café")
    #expect(throws: SourceError.matchCount(2)) { try matches.only() }
    #expect(throws: SourceError.matchCount(0)) {
      try whole.matches(of: /absent/).only()
    }
    #expect(whole.text.hasSuffix("\r\n"))
  }

  @Test("Nested slices retain absolute UTF-8 positions after Unicode prefix")
  func nonzeroSliceOffsets() throws {
    let file = try FileCollector.collect(
      source: "//é🦊\nlet values = [\"🦊\", \"🦊\"]\n",
      path: "/virtual/Unicode.swift"
    )
    let array = try file.source.slice(22..<38)
    let fox = try array.slice(2..<6)

    #expect(array.range == 22..<38)
    #expect(array.text == "[\"🦊\", \"🦊\"]")
    #expect(fox.range == 24..<28)
    #expect(fox.text == "🦊")
    let edit = fox.replacement(with: "fox")
    #expect(edit.source.range == 24..<28)
    #expect(edit.source.text == "🦊")
    #expect(edit.replacement == "fox")
  }

  @Test("Nested regex matches retain absolute positions for repeated Unicode")
  func nonzeroRegexOffsets() throws {
    let file = try FileCollector.collect(
      source: "//é🦊\nlet values = [\"🦊\", \"🦊\"]\n",
      path: "/virtual/Unicode.swift"
    )
    let array = try file.source.slice(22..<38)
    let matches = array.matches(of: /🦊/)

    #expect(matches.map(\.range) == [24..<28, 32..<36])
    #expect(matches.map(\.text) == ["🦊", "🦊"])
    let edits = matches.map { $0.replacement(with: "fox") }
    #expect(edits.map(\.source.range) == [24..<28, 32..<36])
    #expect(edits.map(\.source.text) == ["🦊", "🦊"])
    #expect(edits.map(\.replacement) == ["fox", "fox"])
  }

  @Test("Nested slices reject ranges outside receiver", arguments: [
    -1..<0, 16..<17,
  ])
  func nonzeroSliceBounds(_ range: Range<Int>) throws {
    let file = try FileCollector.collect(
      source: "//é🦊\nlet values = [\"🦊\", \"🦊\"]\n",
      path: "/virtual/Unicode.swift"
    )
    let array = try file.source.slice(22..<38)

    #expect(throws: SourceError.rangeOutOfBounds) { try array.slice(range) }
  }

  @Test("Slicing rejects split UTF-8 scalars and external ranges")
  func checkedRanges() throws {
    let file = try FileCollector.collect(
      source: "//🦊",
      path: "/virtual/Unicode.swift"
    )
    let source = try file.source
    #expect(try source.slice(2..<6).text == "🦊")
    for range in [2..<3, 3..<6, -1..<1, 0..<7] {
      #expect(throws: SourceError.rangeOutOfBounds) { try source.slice(range) }
    }
    #expect(try source.slice(6..<6).text.isEmpty)
  }

  @Test("Synthetic and decoded models cannot supply source")
  func rejectsUnbackedModels() throws {
    let file = try FileCollector.collect(
      source: "import Foundation\nfunc check() { run(value: 1) }",
      path: "/virtual/App.swift"
    )
    let original = file.imports[0]
    let synthetic = Import(name: original.name, location: original.location)
    #expect(original == synthetic)
    #expect(throws: SourceError.unavailable) { _ = try synthetic.source }
    let decoded = try JSONDecoder().decode(
      Import.self, from: JSONEncoder().encode(original)
    )
    #expect(decoded == original)
    #expect(throws: SourceError.unavailable) { _ = try decoded.source }
    let argument = try #require(file.calls.first?.arguments.first)
    let decodedArgument = try JSONDecoder().decode(
      FunctionCall.Argument.self, from: JSONEncoder().encode(argument)
    )
    #expect(decodedArgument == argument)
    let fragment = try #require(decodedArgument.expression)
    #expect(throws: SourceError.unavailable) { _ = try fragment.source }
  }

  @Test("Source transport preserves exact bytes and validates ranges")
  func transportValidation() throws {
    let file = try FileCollector.collect(
      source: "//🦊",
      path: "/virtual/App.swift"
    )
    let source = try file.source
    let fix = SourceFix(
      "Change comment",
      edits: [source.replacement(with: "// fox")]
    )
    let decoded = try JSONDecoder().decode(
      SourceFix.self,
      from: JSONEncoder().encode(fix)
    )
    #expect(decoded == fix)
    var object = try #require(
      JSONSerialization
        .jsonObject(with: JSONEncoder().encode(source)) as? [String: Any]
    )
    object["range"] = [2, 3]
    let malformed = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SourceSlice.self, from: malformed)
    }
  }

  @Test("Canonical Unicode equality cannot hide changed bytes")
  func exactByteIdentity() throws {
    let first = try FileCollector.collect(
      source: "//é",
      path: "/virtual/App.swift"
    ).source
    let second = try FileCollector.collect(
      source: "//e\u{301}",
      path: "/virtual/App.swift"
    ).source
    #expect(first.text == second.text)
    #expect(first.file != second.file)
    let firstEdit = first.replacement(with: "é")
    let secondEdit = first.replacement(with: "e\u{301}")
    #expect(firstEdit != secondEdit)
    #expect(Set([firstEdit, secondEdit]).count == 2)
  }

  @Test("AST replacement preserves outer comments and targets exact node")
  func syntaxReplacement() throws {
    let file = try FileCollector.collect(
      source: "// keep\nlet values = [0xff, 0xff] // keep too\n",
      path: "/virtual/App.swift"
    )
    let integers = file.syntaxNodes(of: .integerLiteral)
    let second = try #require(integers.last)
    let edit = try second.source.replacing(as: IntegerLiteralExprSyntax.self) {
      $0.with(\.literal, .integerLiteral("0xFF"))
    }
    #expect(edit.replacement == "0xFF")
    #expect(try edit.source.range == second.source.range)
    #expect(throws: SourceError.syntaxMismatch) {
      try second.source.replacing(as: ClassDeclSyntax.self) { $0 }
    }
  }
}
