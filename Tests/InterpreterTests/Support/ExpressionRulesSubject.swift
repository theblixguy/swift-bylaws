private struct LogText: ExpressibleByStringInterpolation {
  init(stringLiteral: String) {}
  init(stringInterpolation: StringInterpolation) {}

  struct StringInterpolation: StringInterpolationProtocol {
    enum Privacy { case `public`, `private` }

    init(literalCapacity: Int, interpolationCount: Int) {}
    mutating func appendLiteral(_ literal: String) {}
    mutating func appendInterpolation(_ value: String, privacy: Privacy) {}
  }
}

private func log(_ message: LogText) {}
private func request(_ url: String) {}

private func runExpressionChecks(user: String) {
  log("User: \(user, privacy: .public)")
  log("User: \(user, privacy: .private)")
  log("Literal privacy: .public")
  request("https://example.com")
  request("http://example.com")
}
