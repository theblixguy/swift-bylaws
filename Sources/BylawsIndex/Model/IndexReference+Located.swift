public import BylawsIndexStore
public import BylawsSemantics

extension IndexReference: Located {
  /// The compiler-recorded source position.
  public var location: DeclarationLocation {
    DeclarationLocation(
      filePath: file,
      line: line,
      column: column
    )
  }
}
