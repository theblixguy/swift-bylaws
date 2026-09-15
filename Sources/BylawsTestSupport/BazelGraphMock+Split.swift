import Foundation

extension BazelGraphMock {
  /// A split dependency with a separate dependency added outside the declared inputs.
  public static let splitJSON = json.replacing(
    #""results": ["#,
    with: #"""
    "results": [
      {"configurationId": 1, "target": {"type": "RULE", "rule": {
        "name": "//app:App", "ruleClass": "app",
        "ruleInput": ["//features:Orders"],
        "configuredRuleInput": [
          {"label": "//features:Orders", "configurationId": 1},
          {"label": "//features:Orders", "configurationId": 2},
          {"label": "//storage:Database", "configurationId": 1}
        ]
      }}},
    """#
  )
}
