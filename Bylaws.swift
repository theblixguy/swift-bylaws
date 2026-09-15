import Bylaws

RuleDiscovery(excluding: ["Distribution/BazelModule/e2e/**"])

let sourcesAndBenchmarks = Codebase(
  including: ["Sources/**", "Benchmarks/Benchmarks/**"],
  swiftLanguageMode: .v6
)

let projectCode = Codebase(
  including: [
    "Sources/**", "Tests/**", "Plugins/**", "Benchmarks/Benchmarks/**",
  ],
  excluding: ["**/.build/**", "Tests/SampleApp/**"],
  swiftLanguageMode: .v6
)

let architecture = Layering(
  Layer("BylawsPaths", files: ["Sources/BylawsPaths/**"]),
  Layer(
    "BylawsSemantics", files: ["Sources/BylawsSemantics/**"],
    mayImport: ["BylawsPaths"]
  ),
  Layer(
    "BylawsCore", files: ["Sources/BylawsCore/**"],
    mayImport: ["BylawsPaths", "BylawsSemantics"]
  ),
  Layer(
    "BylawsInterpreter", files: ["Sources/BylawsInterpreter/**"],
    mayImport: ["BylawsCore", "BylawsPaths", "BylawsSemantics"]
  ),
  Layer(
    "Bylaws", files: ["Sources/Bylaws/**"],
    mayImport: ["BylawsCore", "BylawsPaths", "BylawsSemantics"]
  ),
  Layer(
    "BylawsIndexStore", files: ["Sources/BylawsIndexStore/**"],
    mayImport: ["BylawsPaths"]
  ),
  Layer(
    "BylawsIndex", files: ["Sources/BylawsIndex/**"],
    mayImport: [
      "BylawsIndexStore", "BylawsCore", "BylawsPaths", "BylawsSemantics",
    ]
  ),
  Layer(
    "BylawsTestSupport", files: ["Sources/BylawsTestSupport/**"],
    mayImport: ["Bylaws", "BylawsPaths"]
  ),
  Layer(
    "BylawsRunner", files: ["Sources/BylawsRunner/**"],
    mayImport: [
      "BylawsInterpreter", "BylawsCore", "BylawsPaths", "BylawsSemantics",
      "BylawsIndex", "BylawsIndexStore",
    ]
  ),
  Layer(
    "BylawsLSP", files: ["Sources/BylawsLSP/**"],
    mayImport: ["BylawsRunner", "BylawsCore", "BylawsPaths", "BylawsSemantics"]
  ),
  Layer(
    "bylaws-cli", files: ["Sources/bylaws-cli/**"],
    mayImport: [
      "BylawsRunner", "BylawsInterpreter", "BylawsCore", "BylawsPaths",
      "BylawsSemantics",
    ]
  ),
  Layer(
    "bylaws-lsp", files: ["Sources/bylaws-lsp/**"],
    mayImport: ["BylawsLSP", "BylawsRunner"]
  )
)

let rules: [Rule] = [
  Rule("module-boundaries", "Modules import permitted dependencies") {
    try await sourcesAndBenchmarks.checkLayering(architecture)
  },

  Rule("testing-imports", "Only testing frontends import Testing") {
    try await sourcesAndBenchmarks.files.outside(
      "Sources/Bylaws",
      "Sources/BylawsIndex"
    )
    .violations(matching: .imports("Testing"))
  },

  Rule(
    "parser-imports",
    "Only parsers import SwiftSyntax and SwiftParser"
  ) {
    try await sourcesAndBenchmarks.files.outside(
      "Sources/BylawsSemantics",
      "Sources/BylawsInterpreter"
    )
    .violations(matching: .imports("SwiftSyntax") || .imports("SwiftParser"))
  },

  Rule(
    "final-classes",
    "Classes are final except LexicalRegionVisitor"
  ) {
    try await sourcesAndBenchmarks.classes
      .violations(of: Matcher<Class>("be final") {
        $0.isFinal || (
          $0.name == "LexicalRegionVisitor"
            && $0.location.fileName == "LexicalRegionVisitor.swift"
        )
      })
  },

  Rule("safe-concurrency", "Sources use checked concurrency annotations") {
    try await sourcesAndBenchmarks.properties
      .violations(matching: .isNonisolatedUnsafe)
    try await sourcesAndBenchmarks.types
      .violations(matching: .declaresInheritance("@unchecked Sendable"))
  },

  Rule("public-protocol-docs", "Public protocols have documentation") {
    try await sourcesAndBenchmarks.protocols.where(.isPublic)
      .violations(of: .hasDocumentation)
  },

  Rule("no-legacy-random", "Code uses SystemRandomNumberGenerator") {
    try await sourcesAndBenchmarks.calls.violations(matching: .named(
      "arc4random",
      "arc4random_uniform"
    ))
  },

  Rule("no-print-logging", "Only CLI calls print") {
    try await sourcesAndBenchmarks.files.outside("Sources/bylaws-cli")
      .violations(matching: .calls("print"))
  },

  Rule("clock-sleep", "Package code uses clocks instead of Task.sleep") {
    try await projectCode.calls.violations(matching: .references("Task.sleep"))
  },

  Rule("stable-dependencies", "Targets depend on more stable targets") {
    try await projectCode.checkDependencyStability(
      ignoring: ["BylawsRunner", "BylawsTestSupport", "CIndexStore"]
    )
  },
]
