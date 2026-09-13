// Swift 6.4 ships this initialiser in the standard library.
#if compiler(<6.4)
  extension Result where Success: ~Copyable {
    package init(catching body: () async throws(Failure) -> Success) async {
      do {
        self = .success(try await body())
      } catch {
        self = .failure(error)
      }
    }
  }
#endif
