import BylawsCore
package import BylawsSemantics

package struct RuntimeError: Error, Sendable, CustomStringConvertible {
  enum Kind: Sendable, Equatable {
    case general
    case undeclaredName
    case cancelled
  }

  let message: String
  let location: DeclarationLocation
  let kind: Kind
  private let underlyingError: (any Error)?

  init(
    message: String,
    location: DeclarationLocation,
    kind: Kind = .general,
    underlyingError: (any Error)? = nil
  ) {
    self.message = message
    self.location = location
    self.kind = kind
    self.underlyingError = underlyingError
  }

  init(wrapping error: any Error, at location: DeclarationLocation) {
    self.init(
      message: error.reportableDescription,
      location: location,
      kind: error is CancellationError ? .cancelled : .general,
      underlyingError: error
    )
  }

  static func undeclaredName(
    _ name: String,
    at location: DeclarationLocation
  ) -> Self {
    Self(
      message: "'\(name)' is not declared",
      location: location,
      kind: .undeclaredName
    )
  }

  package var description: String {
    "\(location.filePath):\(location.line):\(location.column): \(message)"
  }

  package var pathsThatDidNotParse: [String]? {
    parseDiagnostics.map { Array(Set($0.map(\.location.filePath))).sorted() }
  }

  package var parseDiagnostics: [SourceParseDiagnostic]? {
    underlyingError.flatMap(Self.parseDiagnostics)
  }

  private static func parseDiagnostics(in error: any Error)
    -> [SourceParseDiagnostic]?
  {
    switch error {
    case let CodebaseError.didNotParse(diagnostics):
      diagnostics
    case let LayeringCheckError.unreadableCodebase(error),
         let RuntimeIndexError.unreadableCodebase(error):
      parseDiagnostics(in: error)
    case let error as RuntimeError:
      error.parseDiagnostics
    default:
      nil
    }
  }
}
