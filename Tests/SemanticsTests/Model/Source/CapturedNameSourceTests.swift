import Testing
@testable import BylawsSemantics

@Suite("Captured name sources")
struct CapturedNameSourceTests {
  @Test("Declaration names retain spelling without loading syntax")
  func declarations() throws {
    let file = try FileCollector.collect(
      source: """
      import struct Module . Item
      class `Class` { init?() {} }
      actor Worker {}
      struct Café { var `repeat` = 1, other = 2 }
      enum Choice { case `default`, ready(Int) }
      protocol Reader {
        func `read`()
        var value: Int { get }
      }
      extension Box . Nested {}
      typealias `Alias` = String
      infix operator <+>
      func <+>(lhs: Int, rhs: Int) -> Int { lhs }
      """, path: "/virtual/Names.swift"
    )
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    let choice = try file.enums.only()
    let reader = try file.protocols.only()
    try #require(file.properties.count == 2)
    try #require(choice.cases.count == 2)
    let names = try [
      file.imports.only().nameSource,
      file.classes.only().nameSource,
      file.initializers.only().nameSource,
      file.actors.only().nameSource,
      file.structs.only().nameSource,
      file.properties[0].nameSource,
      file.properties[1].nameSource,
      file.enums.only().nameSource,
      choice.cases[0].nameSource,
      choice.cases[1].nameSource,
      file.protocols.only().nameSource,
      reader.requiredFunctions.only().nameSource,
      reader.requiredProperties.only().nameSource,
      file.extensions.only().nameSource,
      file.typealiases.only().nameSource,
      file.functions.only().nameSource,
    ]

    #expect(names.map(\.text) == [
      "Module . Item", "`Class`", "init", "Worker", "Café", "`repeat`", "other",
      "Choice", "`default`", "ready", "Reader", "`read`", "value",
      "Box . Nested", "`Alias`", "<+>",
    ])
    #expect(file.sourceBuffer.hasLoadedSnapshot)
    #expect(file.sourceBuffer.snapshot?.parsedTree == nil)
  }

  @Test("Callees retain exact spans without loading syntax", arguments: [
    ("receiver . `repeat` ()", "receiver . `repeat`"),
    ("factory<Int>!()", "factory<Int>!"),
    ("factory?()", "factory?"),
    ("({ 1 })()", "({ 1 })"),
    ("outer(inner())()", "outer(inner())"),
    ("café.load<Item>()", "café.load<Item>"),
    ("Self.init()", "Self.init"),
    (".make()", ".make"),
    ("(+)(1, 2)", "(+)"),
  ])
  func callees(expression: String, expected: String) throws {
    let file = try FileCollector.collect(
      source: "let result = \(expression)", path: "/virtual/Calls.swift"
    )
    let call = try #require(file.calls
      .first { $0.calledExpression == expected })
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    let name = try call.nameSource
    let callee = try call.calledExpressionSource

    #expect(name.text == expected)
    #expect(callee.text == expected)
    #expect(name.range == 13..<(13 + expected.utf8.count))
    #expect(callee.range == name.range)
    #expect(file.sourceBuffer.snapshot?.parsedTree == nil)
  }

  @Test("Repeated Unicode names keep distinct original ranges")
  func repeatedNames() throws {
    let file = try FileCollector.collect(
      source: "\u{FEFF}struct Café { let café = 1 }\r\nstruct Other { let café = 2 }\r\n",
      path: "/virtual/Names.swift"
    )
    let names = try file.properties.map { try $0.nameSource }

    #expect(names.map(\.text) == ["café", "café"])
    #expect(names.map(\.range) == [22..<27, 54..<59])
    #expect(file.sourceBuffer.snapshot?.parsedTree == nil)
  }

  @Test("Macro names retain expression and declaration spans", arguments: [
    ("#`repeat`()", "#`repeat`"),
    ("struct Generated { #makeMembers() }", "#makeMembers"),
  ])
  func macros(source: String, expected: String) throws {
    let file = try FileCollector.collect(
      source: source, path: "/virtual/Macros.swift"
    )
    let macro = try #require(file.macroExpansions.first)

    #expect(try macro.nameSource.text == expected)
    #expect(try macro.calledExpressionSource.text == expected)
    #expect(file.sourceBuffer.snapshot?.parsedTree == nil)
  }

  @Test("Name sources retain parsed ranges after reporting locations change")
  func reportingLocation() throws {
    let file = try FileCollector.collect(
      source: "func first() {}\nfunc second() {}", path: "/virtual/Names.swift"
    )
    try #require(file.functions.count == 2)
    var function = file.functions[1]
    function.location = file.functions[0].location
    let name = try function.nameSource

    #expect(name.text == "second")
    #expect(name.range == 21..<27)
    #expect(file.sourceBuffer.snapshot?.parsedTree == nil)
  }
}
