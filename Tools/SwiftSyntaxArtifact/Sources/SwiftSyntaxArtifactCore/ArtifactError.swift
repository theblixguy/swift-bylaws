package struct ArtifactError: Error, CustomStringConvertible, Equatable {
  package let description: String

  package init(_ description: String) {
    self.description = description
  }
}
