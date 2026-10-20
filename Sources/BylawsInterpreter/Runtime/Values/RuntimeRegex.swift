import BylawsSemantics

struct RuntimeRegex: Sendable {
  let pattern: String

  func compiled(at location: DeclarationLocation)
    throws(RuntimeError) -> Regex<AnyRegexOutput>
  {
    do {
      return try Regex(pattern)
    } catch {
      throw RuntimeError(
        message: "cannot read regex: \(error)",
        location: location
      )
    }
  }
}
