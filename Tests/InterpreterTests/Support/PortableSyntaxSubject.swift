import Foundation

func updateSharedState() {
  let lock = NSLock()
  lock.lock()
  defer { lock.unlock() }
  _ = lock
}

func readSharedState() {
  let lock = NSLock()
  lock.withLock {}
}
