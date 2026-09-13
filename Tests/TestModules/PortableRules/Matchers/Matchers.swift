import Bylaws
import PortableRuleSupport

nonisolated func internalHasAtMostOneFunction(
  _ declaration: Class
) -> Bool {
  hasAtMostOneFunction(declaration)
}
