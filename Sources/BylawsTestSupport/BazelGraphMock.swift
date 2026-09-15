/// Bazel query data shared by graph and interpreter tests.
public enum BazelGraphMock {
  /// A feature with different dependencies in two build configurations.
  public static let json = #"""
  {
    "configurations": [
      {"id": 1, "checksum": "debug"},
      {"id": 2, "checksum": "release"}
    ],
    "results": [
      {"configurationId": 1, "target": {"type": "RULE", "rule": {
        "name": "//features:Orders", "ruleClass": "swift_library",
        "location": "features/BUILD.bazel:8:3",
        "attribute": [{"name": "tags", "stringListValue": ["feature"]}],
        "ruleInput": ["//services:Store"],
        "configuredRuleInput": [{"label": "//services:Store", "configurationId": 1, "configurationChecksum": "debug"}]
      }}},
      {"configurationId": 2, "target": {"type": "RULE", "rule": {
        "name": "//features:Orders", "ruleClass": "swift_library",
        "location": "features/BUILD.bazel:8:3",
        "attribute": [{"name": "tags", "stringListValue": ["feature"]}],
        "ruleInput": ["//services:Store"],
        "configuredRuleInput": [{"label": "//services:Store", "configurationId": 2}]
      }}},
      {"configurationId": 1, "target": {"type": "RULE", "rule": {
        "name": "//services:Store", "ruleClass": "swift_library",
        "configuredRuleInput": [{"label": "//storage:Database", "configurationId": 1}]
      }}},
      {"configurationId": 2, "target": {"type": "RULE", "rule": {
        "name": "//services:Store", "ruleClass": "swift_library",
        "configuredRuleInput": [{"label": "//storage:Memory", "configurationId": 2}]
      }}},
      {"configurationId": 1, "target": {"type": "RULE", "rule": {
        "name": "//storage:Database", "ruleClass": "swift_library",
        "configuredRuleInput": [{"label": "//storage:Database.swift"}]
      }}},
      {"configurationId": 2, "target": {"type": "RULE", "rule": {
        "name": "//storage:Memory", "ruleClass": "swift_library"
      }}},
      {"target": {"type": "SOURCE_FILE", "sourceFile": {
        "name": "//storage:Database.swift", "location": "storage/Database.swift:1:1"
      }}}
    ]
  }
  """#
}
