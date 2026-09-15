import Bylaws

let codebase = Codebase(root: .automatic(), including: ["Cases/Sources/**"])

let rules: [Rule] = [
  Rule("references", "Permitted references") {
    try await codebase.checkDependencies(
      from: ["Cases/Sources/**"],
      allowingReferencesTo: []
    )
  },
]
