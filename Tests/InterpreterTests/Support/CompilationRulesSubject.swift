private struct ServiceSettings {
  var allowsInsecureConnections = false

  mutating func configure() {
    #if DEBUG
      allowsInsecureConnections = true
    #else
      allowsInsecureConnections = true
    #endif
    #if !DEBUG
      allowsInsecureConnections = true
    #endif
  }
}

#if DEBUG
  private struct DebugStore {}
#endif
private struct DebugOtherStore {}
