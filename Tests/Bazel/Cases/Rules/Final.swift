import Bylaws

let codebase = Codebase(root: .automatic(), including: ["Cases/Sources/**"])

Rule("final-classes", "Final classes") {
  try await codebase.classes.violations(of: .isFinal)
}
