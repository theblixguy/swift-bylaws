import Bylaws
import Testing

let correctionCodebase = Codebase(including: ["Sources/**"])
let correctionRules = [
  Rule("final-classes", "Classes are final") {
    try await correctionCodebase.classes.violations(of: .isFinal)
      .withFix("Make class final") { context in
        try context.source.slice(0..<0).replacement(with: "final ")
      }
  },
]
