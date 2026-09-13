import BylawsCore
import BylawsIndex
import BylawsIndexStore
import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing

@Suite(
  "Folder dependencies from compiler data",
  .enabled(
    if: ToolchainPaths.activeCompilerPath() != nil && IndexStoreLocation
      .toolchainLibraryPath() != nil,
    "The active toolchain supplies no compiler or index library."
  ),
  .tags(.indexStore)
)
struct DependencyIntegrationTests {
  @Test(
    "Compiler references identify implementation dependencies and API cycles",
    arguments: [("Features", "API"), ("Subsystems", "Contracts")]
  )
  func compilerReferences(
    folder: String,
    interfaceFolder: String
  ) async throws {
    let sources = [
      "Sources/\(folder)/Orders/Order.swift": "struct Order { let payment: Payment; let api: PaymentsAPI }",
      "Sources/\(folder)/Orders/\(interfaceFolder)/OrdersAPI.swift": "protocol OrdersAPI {}",
      "Sources/\(folder)/Payments/Payment.swift": "struct Payment { let api: OrdersAPI }",
      "Sources/\(folder)/Payments/\(interfaceFolder)/PaymentsAPI.swift": "protocol PaymentsAPI {}",
    ]
    let project = try TemporaryProject(files: sources
      .merging(["Package.swift": ""]) { _, value in value })
    let store = project.rootURL
      .appendingPathComponent(".build/debug/index/store")
    try FileManager.default.createDirectory(
      at: store,
      withIntermediateDirectories: true
    )
    let process = Process()
    process
      .executableURL =
      URL(fileURLWithPath: try #require(ToolchainPaths.activeCompilerPath()))
    process.arguments = [
      "-c", "-module-name", "App", "-index-store-path", store.path,
      "-module-cache-path",
      project.rootURL.appendingPathComponent("module-cache").path,
    ] + sources.keys.sorted().map { project.fileURL(for: $0).path }
    process.currentDirectoryURL = project.rootURL
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    let output = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    try #require(
      process.terminationStatus == 0,
      "\(String(decoding: output, as: UTF8.self))"
    )
    let app = Codebase(
      root: .directory(project.rootURL.path),
      including: ["Sources/**"]
    )
    let index = try await app.projectIndex(modules: ["App"])
    try #require(!index.definitions(of: "Order").isEmpty)
    try #require(!index.definitions(of: "Payment").isEmpty)

    let findings = try await app.checkDependencies(
      from: ["Sources/\(folder)/**"],
      allowingReferencesTo: ["Sources/\(folder)/*/\(interfaceFolder)/**"],
      allowingWithinFoldersMatching: "Sources/\(folder)/*",
      modules: ["App"]
    )

    #expect(findings.warnings.isEmpty)
    #expect(findings.violations.offenders.contains { $0.name == "Payment" })
    #expect(findings.violations.count == 1)

    let groups = try await app
      .dependencyGroups(inFoldersMatching: "Sources/\(folder)/*")
    let cycles = try await app.checkDependencyCycles(
      between: groups, modules: ["App"]
    )

    #expect(cycles.warnings.isEmpty)
    #expect(cycles.violations.offenders
      .count(
        where: { $0.description.hasPrefix("dependency cycle:") }
      ) ==
      2)
    #expect(findings.violations.offenders
      .allSatisfy { $0.location.filePath.hasPrefix(project.rootURL.path) })
  }
}
