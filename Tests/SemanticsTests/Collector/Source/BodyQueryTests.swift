import BylawsSemantics
import Testing

@Suite("Source body queries")
struct BodyQueryTests {
  @Test("Assignment values retain complete operator expressions")
  func assignmentValues() throws {
    let file = try collect("""
    func configure() {
      settings.enabled = first && second
      count += step * 2
      text = "é" + suffix
      flag = condition ? first : second
      result = first <~> second
      settings["key"] = .public
      let comparison = first == second
      use(flag: true)
    }
    """)
    let assignments = file.assignments
    #expect(assignments.map(\.name) == [
      "settings.enabled", "count", "text", "flag", "result",
      "settings[\"key\"]",
    ])
    #expect(assignments.map(\.operatorName) == ["=", "+=", "=", "=", "=", "="])
    #expect(assignments.map(\.value.text) == [
      "first && second", "step * 2", "\"é\" + suffix",
      "condition ? first : second", "first <~> second", ".public",
    ])
    #expect(assignments.map(\.value.location.line) == [2, 3, 4, 5, 6, 7])
    #expect(assignments.first?.value.location.column == 22)
    #expect(assignments.first?.value.enclosingDeclarations
      .map(\.name) == ["configure"])
    #expect(assignments.last?.value.referenceName == "public")
  }

  @Test("Assignments include initialisers, accessors and nested closures")
  func assignmentScopes() throws {
    let file = try collect("""
    struct Store {
      init() { flag = false }
      var value: Bool {
        get { flag = true; return flag }
        set { flag = newValue }
      }
      func update() {
        let action = { flag = false }
        func local() { flag = true }
      }
    }
    """)
    #expect(file.assignments.map { $0.enclosingDeclarations.map(\.name) } == [
      ["init", "Store"], ["get", "value", "Store"],
      ["set", "value", "Store"], ["action", "update", "Store"],
      ["local", "update", "Store"],
    ])
  }

  @Test("Bindings retain patterns, mutability and optional initial values")
  func bindings() throws {
    let file = try collect("""
    let global = "https://example.com"
    struct Store {
      var missing: String
      func update() {
        let token = "secret", count = 0
        var (key, value) = pair
        let action = { let nested = false }
      }
    }
    """)
    let bindings = file.variableBindings
    #expect(bindings.map(\.name) == [
      "global", "missing", "token", "count", "(key, value)", "action", "nested",
    ])
    #expect(bindings.map(\.isMutable) == [
      false,
      true,
      false,
      false,
      true,
      false,
      false,
    ])
    #expect(bindings.first?.initialValue?.stringValue == "https://example.com")
    #expect(bindings[1].initialValue == nil)
    #expect(bindings[1].enclosingDeclarations.map(\.name) == ["Store"])
    #expect(bindings[2].initialValue?.stringValue == "secret")
    #expect(bindings[3].initialValue?.integerValue == 0)
    #expect(bindings[4].initialValue?.referenceName == "pair")
    #expect(bindings.last?.enclosingDeclarations.map(\.name) == [
      "action",
      "update",
      "Store",
    ])
    #expect(bindings[2].location.line == 5)
    #expect(bindings[2].location.column == 9)
  }

  @Test(
    "References retain enclosing declarations and distinguish source spellings"
  )
  func references() throws {
    let file = try collect("""
    struct Store {
      func save() { use(Security.kSecAttrAccessibleAlways) }
      func other() { let kSecAttrAccessibleAlways = 0; use(kSecAttrAccessibleAlways) }
    }
    """)
    let references = file.expressions
      .filter { $0.referenceName == "kSecAttrAccessibleAlways" }
    #expect(references.map(\.base?.referenceName) == ["Security", nil])
    #expect(references.map { $0.enclosingDeclarations.map(\.name) } == [
      ["save", "Store"], ["other", "Store"],
    ])
    #expect(references.first?.enclosingDeclarations.first?.location.line == 2)
  }

  @Test("Body queries include every conditional-compilation branch")
  func branches() throws {
    let file = try collect("""
    #if DEBUG
    let enabled = true
    flag = true
    #else
    let enabled = false
    flag = false
    #endif
    """)
    #expect(file.variableBindings.map(\.initialValue?.booleanValue) == [
      true,
      false,
    ])
    #expect(file.assignments.map(\.value.booleanValue) == [true, false])
  }

  private func collect(_ source: String) throws -> SourceFile {
    try FileCollector.collect(source: source, path: "/virtual/Body.swift")
  }

  @Test("Optional bindings preserve explicit and shorthand initialisers")
  func optionalBindings() throws {
    let file = try collect("""
    func configure(token: String?) {
      guard let token else { return }
      if var value = Int(token) { value += 1 }
      while let value = next() { use(value) }
    }
    """)
    #expect(file.variableBindings.map(\.name) == ["token", "value", "value"])
    #expect(file.variableBindings.map(\.isMutable) == [false, true, false])
    #expect(file.variableBindings.map(\.initialValue?.text) == [
      nil,
      "Int(token)",
      "next()",
    ])
    #expect(file.variableBindings
      .map { $0.enclosingDeclarations.map(\.name) } == [
        ["configure"],
        ["configure"],
        ["configure"],
      ])
  }
}
