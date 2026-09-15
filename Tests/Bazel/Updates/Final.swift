import Bylaws

let codebase = Codebase(root: .automatic(), including: ["Cases/Sources/**"])

Rule("final-classes", "Final types") {
  try await codebase.classes.violations(of: .isFinal)
}
