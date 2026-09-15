enum SourceLocationCalls {
  static func save(_ value: Int) {}
  static func save(_ value: String) {}

  static func check() {
    ["é"].forEach { _ in save(1) }
    save("value")
    do {
      let save: (Int) -> Void = { _ in }
      save(2)
    }
  }
}
