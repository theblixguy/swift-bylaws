extension BazelGraphMock {
  /// A tool configuration with grouped platform and user-defined settings.
  public static let settingsJSON = #"""
  {
    "configurations": [{
      "id": 1, "checksum": "exec", "isTool": true,
      "fragmentOptions": [
        {"name": "CoreOptions", "options": [
          {"name": "compilation_mode", "value": "opt"},
          {"name": "unrelated_option", "value": "true"}
        ]},
        {"name": "PlatformOptions", "options": [
          {"name": "platforms", "value": "[//platforms:phone]"}
        ]},
        {"name": "user-defined", "options": [
          {"name": "//settings:api", "value": "v2"}
        ]},
        {"name": "OtherOptions", "options": [
          {"name": "compilation_mode", "value": "custom"}
        ]},
        {"name": "EmptyOptions"}
      ]
    }],
    "results": [{"configurationId": 1, "target": {"type": "RULE", "rule": {
      "name": "//tools:Compiler", "ruleClass": "swift_binary"
    }}}]
  }
  """#
}
