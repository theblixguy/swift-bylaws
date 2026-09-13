actor SessionStore {
  var startCount = 0

  func begin() {
    startCount += 1
  }
}
