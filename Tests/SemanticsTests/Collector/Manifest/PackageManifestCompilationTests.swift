import BylawsSemantics
import Testing

@Suite("Manifest compilation conditions")
struct PackageManifestCompilationTests {
  @Test("Boolean conditions select target mutations", arguments: [
    ("os(macOS) || !os(macOS)", true),
    ("os(macOS) && !os(macOS)", false),
    ("!(os(macOS) && !os(macOS))", true),
    ("UNKNOWN || (os(macOS) || !os(macOS))", true),
    ("UNKNOWN && (os(macOS) && !os(macOS))", false),
    ("os(macOS) && !os(macOS) || !os(macOS) || os(macOS)", true),
    ("(os(macOS) || !os(macOS)) && os(macOS) && !os(macOS)", false),
  ])
  func selectedBranch(condition: String, includesTarget: Bool) {
    let manifest = PackageManifest(source: """
    let package = Package(name: "App", targets: [])
    #if \(condition)
    package.targets.append(.target(name: "App"))
    #else
    package.targets.append(.target(name: "Other"))
    #endif
    """)

    #expect(manifest.targets.values?.map(\.name)
      == [includesTarget ? "App" : "Other"])
  }

  @Test("Unknown conditions preserve conditional targets", arguments: [
    "UNKNOWN || (os(macOS) && !os(macOS))",
    "UNKNOWN && (os(macOS) || !os(macOS))",
    "!UNKNOWN",
  ])
  func unknownCondition(condition: String) {
    let manifest = PackageManifest(source: """
    let package = Package(name: "App", targets: [])
    #if \(condition)
    package.targets.append(.target(name: "App"))
    #endif
    """)

    #expect(manifest.targets.values == nil)
    #expect(manifest.targets.conditionalValues.map(\.name) == ["App"])
  }
}
