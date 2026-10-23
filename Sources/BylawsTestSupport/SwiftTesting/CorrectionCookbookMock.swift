import Testing

package struct CorrectionCookbookMock: Sendable {
  package let ruleID: String
  package let article: String
  package let sources: [String: String]
  package let expected: [String: String]

  package static let cases: [Self] = [
    Self(
      ruleID: "uppercase-hex-digits", article: "CorrectingSourceCookbook",
      sources: ["Sources/Mask.swift": """
      let mask = 0xdead_Beef
      let plain = 255
      let text = "0xff"
      // 0xab
      """],
      expected: ["Sources/Mask.swift": """
      let mask = 0xDEAD_BEEF
      let plain = 255
      let text = "0xff"
      // 0xab
      """]
    ),
    Self(
      ruleID: "binary-plus-spacing", article: "CorrectingSourceCookbook",
      sources: [
        "Sources/Math/Total.swift": """
        let count = 1+2
        let sign = +3
        let text = "1+2"
        """,
        "Sources/Other/Total.swift": "let untouched = 4+5",
      ],
      expected: [
        "Sources/Math/Total.swift": """
        let count = 1 + 2
        let sign = +3
        let text = "1+2"
        """,
        "Sources/Other/Total.swift": "let untouched = 4+5",
      ]
    ),
    Self(
      ruleID: "comment-markers", article: "CorrectingSourceCookbook",
      sources: ["Sources/Comments.swift": """
      let note = "FIXME"
      // FIXME: adjust cache
      /// FIXME: API note
      /* FIXME: another policy */
      let count = 1
      """],
      expected: ["Sources/Comments.swift": """
      let note = "FIXME"
      // TODO: adjust cache
      /// FIXME: API note
      /* FIXME: another policy */
      let count = 1
      """]
    ),
    Self(
      ruleID: "registered-screen-name", article: "CorrectingSourceCookbook",
      sources: [
        "Sources/LegacyScreen.swift": "class LegacyScreen {}",
        "Sources/Registry.swift": "let registered = \"LegacyScreen\"",
        "Sources/Other.swift": "let title = \"LegacyScreen\"",
      ],
      expected: [
        "Sources/LegacyScreen.swift": "class AccountScreen {}",
        "Sources/Registry.swift": "let registered = \"AccountScreen\"",
        "Sources/Other.swift": "let title = \"LegacyScreen\"",
      ]
    ),
    Self(
      ruleID: "observable-first", article: "FormattingCookbook",
      sources: [
        "Sources/Screen.swift": "@MainActor\n@Observable class Screen {}",
      ],
      expected: [
        "Sources/Screen.swift": "@Observable @MainActor\nclass Screen {}",
      ]
    ),
    Self(
      ruleID: "property-groups", article: "FormattingCookbook",
      sources: ["Sources/Panel.swift": #"""
      struct Panel {
        let completion: () -> Void
        @State private var query = ""
        @Environment(Settings.self) private var settings
        private let store: Store
        @Environment(\.locale) private var locale
        var footer = 0
        func render() {}
        @State private var later = 0
      }

      struct DividedPanel {
        @State private var selected = false
        let title: String
        var separator = 0
        let count: Int
        @Environment(\.locale) private var locale
      }

      struct Constants {
        let title: String
        private let count: Int
      }

      struct SeveralBindings {
        let first = 1, second = 2
        @State private var selected = false
      }

      struct Empty {}
      """#],
      expected: ["Sources/Panel.swift": #"""
      struct Panel {
        @Environment(\.locale) private var locale
        @Environment(Settings.self) private var settings

        @State private var query = ""

        private let store: Store
        let completion: () -> Void
        var footer = 0
        func render() {}
        @State private var later = 0
      }

      struct DividedPanel {
        @State private var selected = false

        let title: String
        var separator = 0
        @Environment(\.locale) private var locale

        let count: Int
      }

      struct Constants {
        private let count: Int
        let title: String
      }

      struct SeveralBindings {
        let first = 1, second = 2
        @State private var selected = false
      }

      struct Empty {}
      """#]
    ),
    Self(
      ruleID: "statement-gaps", article: "FormattingCookbook",
      sources: ["Sources/Refresh.swift": """
      func refresh() async throws {
        let request = try makeRequest()
        await record(request)
        try await save(request)
        let count = 1
        let limit = 2
        let first = makeFirst()
        let second = makeSecond()
      }

      func nestedCalls() {
        let count = 1
        if ready { record() }
        let next = 2
        let callback = { record() }
        let last = 3
      }

      func wrappedCalls() async throws {
        record()
        let count = 1
        try? save()
        await update()
        let next = 2
        try! load()
      }
      """],
      expected: ["Sources/Refresh.swift": """
      func refresh() async throws {
        let request = try makeRequest()

        await record(request)

        try await save(request)

        let count = 1
        let limit = 2
        let first = makeFirst()
        let second = makeSecond()
      }

      func nestedCalls() {
        let count = 1
        if ready { record() }
        let next = 2
        let callback = { record() }
        let last = 3
      }

      func wrappedCalls() async throws {
        record()

        let count = 1

        try? save()

        await update()

        let next = 2

        try! load()
      }
      """]
    ),
    Self(
      ruleID: "argument-width", article: "FormattingCookbook",
      sources: ["Sources/Send.swift": """
      let value = send(first: "First delivery batch", second: "Cached delivery data", third: "Latest delivery time")
      """],
      expected: ["Sources/Send.swift": """
      let value = send(first: "First delivery batch", second: "Cached delivery data",
                       third: "Latest delivery time")
      """]
    ),
    Self(
      ruleID: "reusable-argument-layout", article: "FormattingCookbook",
      sources: ["Sources/Send.swift": "let result = send(first: 1, second: 2)"],
      expected: ["Sources/Send.swift": """
      let result = send(
          first: 1, second: 2
      )
      """]
    ),
    Self(
      ruleID: "logging-layout", article: "FormattingCookbook",
      sources: ["Sources/Log.swift": """
      let entry = logger.write(.info, "Ready", category: "Transfer", tags: ["ready", "cached"])
      """],
      expected: ["Sources/Log.swift": """
      let entry = logger.write(
        .info, "Ready",
        category: "Transfer",
        tags: [
          "ready",
          "cached"
        ]
      )
      """]
    ),
    Self(
      ruleID: "condition-width", article: "FormattingCookbook",
      sources: ["Sources/Conditions.swift": """
      if isReady, isConnected, hasAccount, isAuthorised, canRefresh, isVisible, isActive, isCurrent {}
      """],
      expected: ["Sources/Conditions.swift": """
      if isReady, isConnected, hasAccount, isAuthorised, canRefresh, isVisible,
         isActive, isCurrent {}
      """]
    ),
  ]
}

extension CorrectionCookbookMock: CustomTestStringConvertible {
  package var testDescription: String { ruleID }
}
