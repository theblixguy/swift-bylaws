import Bylaws
import CompanyRules

nonisolated let app = Codebase(
  root: .automatic(),
  including: ["Sources/**"]
)
nonisolated let rules = companyRules(for: app)
