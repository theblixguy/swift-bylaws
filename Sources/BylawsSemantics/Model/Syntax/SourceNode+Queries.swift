extension SourceNode {
  /// Returns whether this node or any represented descendant has the kind.
  ///
  /// The search includes nested declarations and closures.
  /// - Complexity: O(n), where n is the number of represented nodes.
  public func contains(_ kind: Kind) -> Bool {
    var pending = [self]
    while let node = pending.popLast() {
      if node.kind == kind { return true }
      pending.append(contentsOf: node.children.reversed())
    }
    return false
  }
}
