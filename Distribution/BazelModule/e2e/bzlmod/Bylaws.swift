import Bylaws

let codebase = Codebase(root: .automatic())

let rules: [Rule] = [
  Rule("final-classes", "Final classes") {
    try await codebase.classes.violations(of: .isFinal)
  },
]
