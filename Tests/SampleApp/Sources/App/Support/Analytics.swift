import Foundation

protocol Titled {}

struct AnalyticsEvent {
  let name: String
  var values: [String: String] = [:]

  static let empty = AnalyticsEvent(name: "empty")

  init(name: String) {
    self.name = name
  }

  func serialized(pretty: Bool) -> String {
    name
  }
}

enum Screen: CaseIterable {
  case home
  case settings

  @MainActor
  static func track(_ screen: Screen) {}
}

extension HomeViewModel: Titled {}
