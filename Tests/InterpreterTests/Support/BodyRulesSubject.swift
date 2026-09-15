private struct Connection {
  var allowsInsecureConnections = false

  mutating func configure() {
    let serviceURL = "http://example.com"
    let secureURL = "https://example.com"
    allowsInsecureConnections = true
    allowsInsecureConnections = false
    _ = (serviceURL, secureURL)
  }
}
