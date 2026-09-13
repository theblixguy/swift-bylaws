package import BylawsCore
package import BylawsInterpreter
package import BylawsSemantics

package enum RuleSelector {
  package struct Selection {
    package let rules: [Rule]
    package let diagnostics: [Diagnostic]
  }

  package static func select(
    from rules: [Rule],
    only: [String],
    skip: [String],
    defaultLocation: DeclarationLocation
  ) -> Selection {
    let available = Set(rules.map(\.id))
    let requested = Set((only + skip).map { Rule.ID($0) })
    let unknown = requested.subtracting(available)
    let availableIDs = rules.map { "'\($0.id)'" }.joined(separator: ", ")
    let diagnostics = unknown.sorted { $0.rawValue < $1.rawValue }.map { id in
      Diagnostic(
        severity: .error,
        location: defaultLocation,
        message: "rule ID '\(id)' does not exist",
        hint: availableIDs.isEmpty ? nil : "available IDs are \(availableIDs)"
      )
    }

    var selected = rules
    if !only.isEmpty {
      let wanted = Set(only.map { Rule.ID($0) })
      selected = selected.filter { wanted.contains($0.id) }
    }
    if !skip.isEmpty {
      let unwanted = Set(skip.map { Rule.ID($0) })
      selected = selected.filter { !unwanted.contains($0.id) }
    }
    return Selection(rules: selected, diagnostics: diagnostics)
  }
}
