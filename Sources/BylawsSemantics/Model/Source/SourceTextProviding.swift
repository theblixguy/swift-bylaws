package protocol SourceTextProviding {
  var source: SourceBuffer { get }
  var sourceRange: Range<Int> { get }
}

extension SourceTextProviding {
  /// The declaration's source text, as written.
  ///
  /// Prefer model properties. Inspect the text only for checks they cannot
  /// express.
  ///
  /// - Complexity: O(n), where n is the number of UTF-8 bytes in the text.
  public var sourceText: String {
    source.text(inUTF8Range: sourceRange)
  }
}
