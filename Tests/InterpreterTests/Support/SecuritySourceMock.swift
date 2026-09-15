enum SecuritySourceMock {
  static let files: [String: String] = [
    "Sources/Logging/Log.swift": #"""
    func write(user: String) {
      let logger = Logger()
      logger.info("User: \(user, privacy: .private)")
      logger.info("User: \(user, privacy: .public)")
      logger.info("Literal privacy: .public")
      logger.info("User: \(user, privacy: OSLogPrivacy.public)")
    }
    """#,
    "Sources/Features/Logging.swift": """
    func load() { Swift.print("loaded") }
    """,
    "Sources/Security/Keychain/Store.swift": """
    func save() {
      let attributes = [kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked]
      SecItemAdd(attributes, nil)
    }
    """,
    "Sources/Features/Keychain.swift": """
    func load() {
      let action = { SecItemCopyMatching(query, nil) }
      let old = [kSecAttrAccessible: kSecAttrAccessibleAlways]
      let other = Security.kSecAttrAccessibleAlwaysThisDeviceOnly
      let text = "kSecAttrAccessibleAlways"
    }
    """,
    "Sources/Networking/Authentication/Trust.swift": """
    func handle(_ challenge: URLAuthenticationChallenge) {
      SecTrustEvaluateWithError(trust, nil)
      URLCredential(trust: trust)
    }
    """,
    "Sources/Features/Authentication.swift": """
    func handle(_ challenge: Foundation.URLAuthenticationChallenge) {}
    let credential = URLCredential(trust: trust)
    """,
    "Sources/Networking/URLs.swift": #"""
    let secure = "https://example.com"
    let plain = "http://example.com"
    let upper = "HTTP://EXAMPLE.COM"
    let raw = #"http://example.com"#
    let escaped = "http:\u{2f}\u{2f}example.com"
    let unknown = serviceURL
    #if DEBUG
    let local = "http://127.0.0.1:8080"
    let credentials = "http://127.0.0.1:8080@evil.example"
    #else
    let local = "http://127.0.0.1:8080"
    #endif
    """#,
    "Sources/Networking/Settings.swift": """
    #if DEBUG
    var allowsInsecureConnections = true
    allowsInsecureConnections = true
    #else
    var allowsInsecureConnections = true
    allowsInsecureConnections = true
    #endif
    allowsInsecureConnections = false
    allowsInsecureConnections = configurationValue
    """,
  ]
}
