import Bylaws
import CompanyRules

let app = Codebase(including: ["Sources/**"])
let rules = companySourceRules(for: app)
