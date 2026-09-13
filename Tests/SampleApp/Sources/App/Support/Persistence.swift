import Foundation

struct PreferencesStore {
  func markSeen() {
    UserDefaults.standard.set(true, forKey: "seen")
  }

  func reset() {
    UserDefaults.standard.removeObject(forKey: "seen")
  }
}
