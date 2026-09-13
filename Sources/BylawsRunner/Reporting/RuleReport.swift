package import BylawsCore
import BylawsInterpreter
package import BylawsSemantics

package struct RuleReport {
  package let id: Rule.ID
  package let name: String
  package let enforcement: Enforcement
  package let hint: String?
  package let location: DeclarationLocation
  package let violations: Violations<Offender>
  package let warnings: [Rule.Warning]

  package init(
    id: Rule.ID,
    name: String,
    enforcement: Enforcement,
    hint: String?,
    location: DeclarationLocation,
    violations: Violations<Offender>,
    warnings: [Rule.Warning]
  ) {
    self.id = id
    self.name = name
    self.enforcement = enforcement
    self.hint = hint
    self.location = location
    self.violations = violations
    self.warnings = warnings
  }
}
