import BylawsSemantics
import Testing

@Suite("Macro and accessor call recording")
struct MacroDuplicationTests {
  @Test("Collector records calls in computed-property accessors")
  func recordsAccessorCalls() throws {
    let file = try FileCollector.collect(
      source: """
      struct Screen {
        var title: String { formatter.string() }
        var subtitle: String {
          get { store.read() }
          set { store.write(newValue) }
        }
      }
      """,
      path: "/virtual/App/Screen.swift"
    )

    let title = try #require(file.properties.first { $0.name == "title" })
    #expect(title.calls("formatter.string"))

    let subtitle = try #require(
      file.properties.first { $0.name == "subtitle" }
    )
    #expect(subtitle.calls("store.read"))
    #expect(subtitle.calls("store.write"))
  }

  @Test("A macro's own body declares nothing for the enclosing type")
  func macroBodyDeclaresNothing() throws {
    let file = try FileCollector.collect(
      source: """
      struct Screen {
        var title = "Home"
        #Preview {
          let model = Model()
          Screen()
        }
      }
      """,
      path: "/virtual/App/Screen.swift"
    )

    #expect(file.properties.map(\.name) == ["title"])
    #expect(file.macroExpansions.map(\.name) == ["#Preview"])
  }

  @Test("Collector records a top-level macro inside a block")
  func recordsMacrosInsideTopLevelBlocks() throws {
    let file = try FileCollector.collect(
      source: """
      #Preview("direct") { Screen() }
      if flag {
        #Preview("in-if") { Screen() }
      }
      """,
      path: "/virtual/App/Previews.swift"
    )

    #expect(file.macroExpansions.count == 2)
    #expect(
      file.macroExpansions.map { $0.arguments.first?.text } == [
        "\"direct\"", "\"in-if\"",
      ]
    )
  }

  @Test("Collector records each macro once")
  func recordsEachMacroOnce() throws {
    let file = try FileCollector.collect(
      source: """
      struct Screen {
        static let shared = make(#function)
        var body: Int {
          #line
        }
        func check() {
          #expect(1 == 1)
        }
        #Preview { Screen() }
      }

      #Preview("Top") { Screen() }
      """,
      path: "/virtual/App/Screen.swift"
    )

    let names = file.calls.filter { $0.name.hasPrefix("#") }.map(\.name)
    #expect(names.sorted() == [
      "#Preview", "#Preview", "#expect", "#function", "#line",
    ].sorted())
    #expect(file.macroExpansions.map(\.name) == ["#Preview", "#Preview"])
  }
}
