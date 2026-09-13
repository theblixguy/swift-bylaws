public import Bylaws

/// Returns whether a class declares at most one function.
public nonisolated func hasAtMostOneFunction(
  _ declaration: Class
) -> Bool {
  declaration.functions.count <= 1
}
