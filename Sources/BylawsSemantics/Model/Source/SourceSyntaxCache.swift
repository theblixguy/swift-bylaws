import BylawsSyntax
import ConcurrencyExtras

final class SourceSyntaxCache: Sendable {
  private let text: String
  private let swiftLanguageMode: SwiftLanguageMode
  private let state: LockIsolated<State>

  private struct State: Sendable {
    var context: SourceSyntaxContext?
    var tokens: [TokenSyntax]?
  }

  init(
    text: String, swiftLanguageMode: SwiftLanguageMode,
    context: SourceSyntaxContext? = nil
  ) {
    self.text = text
    self.swiftLanguageMode = swiftLanguageMode
    state = LockIsolated(State(context: context))
  }

  var cachedContext: SourceSyntaxContext? {
    state.value.context
  }

  var context: SourceSyntaxContext {
    state.withValue { context(in: &$0) }
  }

  func token(at offset: Int) -> TokenSyntax? {
    state.withValue { state in
      let tree = context(in: &state).tree
      guard offset >= tree.position.utf8Offset,
            offset < tree.endPosition.utf8Offset else { return nil }
      let tokens = state.tokens ?? Array(tree.tokens(viewMode: .sourceAccurate))
      state.tokens = tokens
      var lower = 0
      var upper = tokens.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if tokens[middle].endPosition.utf8Offset <= offset {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      guard lower < tokens.count,
            tokens[lower].position.utf8Offset <= offset else { return nil }
      return tokens[lower]
    }
  }

  private func context(in state: inout State) -> SourceSyntaxContext {
    if let context = state.context { return context }
    let context = SourceSyntaxContext(
      tree: swiftLanguageMode.parse(text), text: text
    )
    state.context = context
    return context
  }
}
