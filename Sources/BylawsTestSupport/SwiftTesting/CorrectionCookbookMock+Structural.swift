extension CorrectionCookbookMock {
  package static let structuralCases: [Self] = [
    Self(
      ruleIDs: ["store-isolation"], article: "StructuralCorrections",
      sources: [
        "Sources/Stores.swift": "class SessionStore {}\n@MainActor class CacheStore {}\nclass Other {}",
      ],
      expected: [
        "Sources/Stores.swift": "@MainActor class SessionStore {}\n@MainActor class CacheStore {}\nclass Other {}",
      ]
    ),
    Self(
      ruleIDs: ["else-if"], article: "StructuralCorrections",
      sources: ["Sources/Flow.swift": """
      func update() {
        if isReady {
          start()
        } else {
          if canRetry {
            retry()
          } else {
            if canWait {
              wait()
            }
          }
        }
      }
      """],
      expected: ["Sources/Flow.swift": """
      func update() {
        if isReady {
          start()
        } else if canRetry {
          retry()
        } else if canWait {
          wait()
        }
      }
      """]
    ),
    Self(
      ruleIDs: ["legacy-identity"], article: "StructuralCorrections",
      sources: [
        "Sources/Values.swift": "let total = legacyIdentity(left + right) * scale\nlet other = different(value)",
      ],
      expected: [
        "Sources/Values.swift": "let total = (left + right) * scale\nlet other = different(value)",
      ]
    ),
  ]
}
