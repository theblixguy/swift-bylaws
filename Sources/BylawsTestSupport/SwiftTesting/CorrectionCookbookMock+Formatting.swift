extension CorrectionCookbookMock {
  package static let formattingCases: [Self] = [
    Self(
      ruleIDs: ["property-groups", "statement-gaps", "argument-lines"],
      article: "FormattingCookbook",
      sources: ["Sources/Callbacks.swift": #"""
      struct Controls {
        let completion: () -> Void
        @State private var selected = false
        @Environment(Settings.self) private var settings
        private let client: Client
        @Environment(\.locale) private var locale

        func refresh() async throws {
          let request = try prepare()
          audit(.info, "Ready", details: [Entry(name: "first", value: 1), Entry(name: "last", value: 2)])
          try await finish(request)
          schedule(request, action: {
            let cached = try load()
            publish(cached, origin: "memory")
          })
        }
      }

      audit(.notice, "Started", category: "Launch")
      """#],
      expected: ["Sources/Callbacks.swift": #"""
      struct Controls {
        @Environment(\.locale) private var locale
        @Environment(Settings.self) private var settings

        @State private var selected = false

        private let client: Client
        let completion: () -> Void

        func refresh() async throws {
          let request = try prepare()

          audit(
            .info, "Ready",
            details: [
              Entry(
                name: "first",
                value: 1
              ),
              Entry(
                name: "last",
                value: 2
              )
            ]
          )

          try await finish(request)

          schedule(
            request,
            action: {
              let cached = try load()

              publish(
                cached,
                origin: "memory"
              )
            }
          )
        }
      }

      audit(
        .notice, "Started",
        category: "Launch"
      )
      """#],
      testDescription: "Combined properties, calls and nested closure spacing"
    ),
    Self(
      ruleIDs: ["property-groups", "statement-gaps", "argument-lines"],
      article: "FormattingCookbook",
      sources: ["Sources/Nested.swift": """
      struct Options {
        let payload = pack(first: 1, second: 2)
        @State private var selected = false

        func update() {
          let value = 1
          emit(.debug, "Cache", values: [pair(first: 1, second: 2)], metadata: ["item": pair(first: 3, second: 4)])
          relay(pair(first: 5, second: 6), token: "next")
          empty(values: [], metadata: [:])
          accept(value)
        }
      }
      """],
      expected: ["Sources/Nested.swift": """
      struct Options {
        @State private var selected = false

        let payload = pack(
          first: 1,
          second: 2
        )

        func update() {
          let value = 1

          emit(
            .debug, "Cache",
            values: [
              pair(
                first: 1,
                second: 2
              )
            ],
            metadata: [
              "item": pair(
                first: 3,
                second: 4
              )
            ]
          )
          relay(
            pair(
              first: 5,
              second: 6
            ),
            token: "next"
          )
          empty(
            values: [],
            metadata: [:]
          )
          accept(value)
        }
      }
      """],
      testDescription: "Nested calls compose with arrays, dictionaries and moved properties"
    ),
    Self(
      ruleIDs: ["property-groups", "statement-gaps", "argument-lines"],
      article: "FormattingCookbook",
      sources: ["Sources/Widths.swift": """
      struct Widths {
        let name: String
        @State private var selected = false

        func refresh() {
          let value = 1
          alpha(first: "xxxxxxxxxxxxxxxxxxxxxxx", payload: pair(first: 1, second: 2))
          bravo(first: "xxxxxxxxxxxxxxxxxxxxxxxx", payload: pair(first: 1, second: 2))
          delta(first: "xxxxxxxxxxxxxxxxxxxxxxxxx", payload: pair(first: 1, second: 2))
          keep(
            first: 1, second: 2
          )
        }
      }
      """],
      expected: ["Sources/Widths.swift": """
      struct Widths {
        @State private var selected = false

        let name: String

        func refresh() {
          let value = 1

          alpha(first: "xxxxxxxxxxxxxxxxxxxxxxx", payload: pair(first: 1, second: 2))
          bravo(first: "xxxxxxxxxxxxxxxxxxxxxxxx", payload: pair(first: 1, second: 2))
          delta(
            first: "xxxxxxxxxxxxxxxxxxxxxxxxx",
            payload: pair(first: 1, second: 2)
          )
          keep(
            first: 1, second: 2
          )
        }
      }
      """],
      maximumWidth: 80,
      testDescription: "Widths 79, 80 and 81 preserve short nested and multiline calls"
    ),
  ]
}
