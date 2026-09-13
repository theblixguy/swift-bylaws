actor DiagnosticRefreshControl {
  private var nextRequestID = 0
  private var pendingRequests: [Int: CheckedContinuation<Void, Never>] = [:]
  private var suspendedRequestCount = 0
  private var suspendedWaiter: (
    minimumCount: Int,
    continuation: CheckedContinuation<Void, Never>
  )?

  func beginRequest() -> Int {
    let requestID = nextRequestID
    nextRequestID += 1
    return requestID
  }

  func suspend(_ requestID: Int) async {
    await withCheckedContinuation { continuation in
      pendingRequests[requestID] = continuation
      suspendedRequestCount += 1
      guard let suspendedWaiter,
            suspendedRequestCount >= suspendedWaiter.minimumCount
      else { return }
      self.suspendedWaiter = nil
      suspendedWaiter.continuation.resume()
    }
  }

  func waitForSuspendedRequests(_ minimumCount: Int) async {
    guard suspendedRequestCount < minimumCount else { return }
    await withCheckedContinuation { continuation in
      precondition(suspendedWaiter == nil)
      suspendedWaiter = (minimumCount, continuation)
    }
  }

  func resumeRequest(_ requestID: Int) {
    precondition(pendingRequests[requestID] != nil)
    pendingRequests.removeValue(forKey: requestID)?.resume()
  }
}
