package struct CodebaseLoading: Sendable {
  package let parseCachePolicy: ParseCachePolicy
  package let overlay: SourceOverlay
  package let source: SourceLoading

  package init(
    parseCachePolicy: ParseCachePolicy,
    overlay: SourceOverlay = .empty,
    preparedSources: PreparedSources? = nil
  ) {
    self.parseCachePolicy = parseCachePolicy
    self.overlay = overlay
    source = preparedSources.map(SourceLoading.prepared) ?? .fileSystem
  }

  package func apply(to codebase: Codebase) -> Codebase {
    var codebase = codebase
      .usingParseCache(parseCachePolicy)
      .usingOverlay(overlay)
    codebase.sourceLoading = source
    return codebase
  }
}

package enum SourceLoading: Sendable, Hashable {
  case fileSystem
  case prepared(PreparedSources)
}
