import BylawsSyntax
import Foundation
import Testing
@testable import BylawsSemantics

@Suite("Progressive source loading")
struct SourceLoadingTests {
  @Test("Text corrections load snapshots without syntax")
  func textCorrection() throws {
    let file = try FileCollector.collect(
      source: "let tint = 0xab\n", path: "/virtual/Colour.swift"
    )
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    let property = try #require(file.properties.first)
    let source = try property.source
    let literal = try source.matches(of: /0x[0-9a-f]+/).only()
    let letters = try literal.matches(of: /[a-f]+/).only()
    let edit = letters.replacement(with: letters.text.uppercased())
    let corrected = try source.file.replacement(applying: [edit])

    #expect(source.text == "tint = 0xab")
    #expect(edit.source.range == 13..<15)
    #expect(corrected.replacement == "let tint = 0xAB\n")
    #expect(file.sourceBuffer.hasLoadedSnapshot)
    #expect(source.snapshot.parsedTree == nil)
  }

  @Test("Named parts load syntax only for requested file")
  func requestedFile() throws {
    let file = try FileCollector.collect(
      source: "struct Café { func read() {} }", path: "/virtual/Café.swift"
    )
    let other = try FileCollector.collect(
      source: "struct Other {}", path: "/virtual/Other.swift"
    )
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    #expect(!other.sourceBuffer.hasLoadedSnapshot)
    let declaration = try #require(file.structs.first)
    let name = try declaration.nameSource
    let tree = try #require(name.snapshot.parsedTree)
    let body = try declaration.bodySource

    #expect(name.text == "Café")
    #expect(name.range == 7..<12)
    #expect(body.text == " func read() {} ")
    #expect(body.snapshot.parsedTree?.id == tree.id)
    #expect(!other.sourceBuffer.hasLoadedSnapshot)
  }

  @Test("Argument inspection defers original snapshot until source access")
  func argumentExpression() throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("bylaws-fragment-\(UUID().uuidString).swift")
    defer { try? FileManager.default.removeItem(at: path) }
    try Data("let value = send(7)\n".utf8).write(to: path)
    let file = try FileCollector.collect(fileAt: path.path)
    let argument = try #require(file.calls.first?.arguments.first)
    let expression = try #require(argument.expression)

    #expect(expression.integerValue == 7)
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    try Data("let value = send(99)\n".utf8).write(to: path)
    let source = try expression.source

    #expect(source.text == "7")
    #expect(source.range == 17..<18)
    #expect(source.file.text == "let value = send(7)\n")
    #expect(file.sourceBuffer.hasLoadedSnapshot)
    #expect(source.snapshot.parsedTree == nil)
  }

  @Test(
    "Lazy projections retain captured bytes after disk changes",
    arguments: [false, true]
  )
  func capturedFile(removingFile: Bool) throws {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("bylaws-lazy-\(UUID().uuidString).swift")
    defer { try? FileManager.default.removeItem(at: path) }
    try Data("func café() { send(label: \"🦊\") }\r\n".utf8).write(to: path)
    let file = try FileCollector.collect(fileAt: path.path)
    #expect(!file.sourceBuffer.hasLoadedSnapshot)

    if removingFile {
      try FileManager.default.removeItem(at: path)
    } else {
      try Data("func changed() {}\n".utf8).write(to: path)
    }

    let function = try #require(file.functions.first)
    #expect(try function.nameSource.text == "café")
    #expect(try function.bodySource.text == " send(label: \"🦊\") ")
    #expect(try function.source.file
      .text == "func café() { send(label: \"🦊\") }\r\n")
  }

  @Test(
    "Concurrent first projections share captured syntax",
    .timeLimit(.minutes(1))
  )
  func concurrentParts() async throws {
    let file = try FileCollector.collect(
      source: "func read() { send(label: 1) }", path: "/virtual/Reader.swift"
    )
    let function = try #require(file.functions.first)
    #expect(!file.sourceBuffer.hasLoadedSnapshot)
    let values = try await withThrowingTaskGroup(
      of: (name: String, body: String, snapshot: SourceSnapshot).self
    ) { group in
      for _ in 0..<32 {
        group.addTask {
          let name = try function.nameSource
          let body = try function.bodySource
          return (name: name.text, body: body.text, snapshot: name.snapshot)
        }
      }
      var values: [(name: String, body: String, snapshot: SourceSnapshot)] = []
      for try await value in group { values.append(value) }
      return values
    }

    #expect(values.count == 32)
    for value in values {
      #expect(value.name == "read")
      #expect(value.body == " send(label: 1) ")
      #expect(value.snapshot.filePath == "/virtual/Reader.swift")
    }
    let treeIDs = try values.map { try #require($0.snapshot.parsedTree).id }
    #expect(Set(treeIDs).count == 1)
  }
}
