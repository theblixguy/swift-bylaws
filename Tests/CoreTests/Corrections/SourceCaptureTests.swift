import BylawsCore
import BylawsTestSupport
import Foundation
import Testing

@Suite("Correction source capture")
struct SourceCaptureTests {
  @Test("Shared source ancestors retain missing manifests")
  func missingManifests() async throws {
    let project = try TemporaryProject(files: [
      "Root.swift": "struct Root {}",
      "Sources/App/One.swift": "struct One {}",
      "Sources/App/Two.swift": "struct Two {}",
      "Sources/App/Nested/Three.swift": "struct Three {}",
      "Sources/Écran/Four.swift": "struct Four {}",
    ])
    let capture = try await SourceCapture.capture(.init(
      rootPath: project.rootURL.path + "/Sources/..",
      selection: .sourceFiles(
        including: ["**"], excluding: ["**/Package.swift"],
        swiftPM: true, xcode: false
      )
    ))
    let missing = Set(capture.inputs.filter { $0.digest == nil }.map(\.path))
    var expectedMissing = Set([
      "Package.resolved",
      ".swiftpm/configuration/mirrors.json",
      ".swiftpm/configuration/registries.json",
    ].map { project.fileURL(for: $0).path })
    for directory in [
      "", "Sources", "Sources/App", "Sources/App/Nested", "Sources/Écran",
    ] {
      let root = directory.isEmpty ? project.rootURL : project.rootURL
        .appendingPathComponent(directory)
      let manifest = root.appendingPathComponent("Package.swift").path
      expectedMissing.insert(manifest)
    }
    #expect(missing == expectedMissing)
    #expect(Set(capture.inputs.map(\.path)).count == capture.inputs.count)
    try await SourceCapture.validate(Array(repeating: capture, count: 20))

    try project.write(
      "// swift-tools-version: 6.2", to: "Sources/App/Package.swift"
    )

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate([capture, capture])
    }
  }

  @Test("New selected source changes file membership")
  func addedSource() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/One.swift": "struct One {}",
    ])
    let capture = try await SourceCapture.capture(scope(in: project))
    try project.write("struct Two {}", to: "Sources/App/Two.swift")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate([capture, capture])
    }
  }

  @Test(
    "Duplicate scopes compare every original capture",
    arguments: [false, true]
  )
  func conflictingOriginals(reversingRecords: Bool) async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/One.swift": "struct One {}",
    ])
    let first = try await SourceCapture.capture(scope(in: project))
    try project.write("struct ChangedOne {}", to: "Sources/App/One.swift")
    let second = try await SourceCapture.capture(first.scope)

    let records = reversingRecords ? [second, first] : [first, second]
    await #expect {
      try await SourceCapture.validate(records)
    } throws: { error in
      (error as? CaptureError)?.description
        .contains("snapshots disagree") == true
    }
  }

  @Test(
    "Missing and present originals conflict in either order",
    arguments: [false, true]
  )
  func conflictingPresence(reversingRecords: Bool) async throws {
    let project = try TemporaryProject(files: [:])
    let scope = SourceCapture.Scope(
      rootPath: project.rootURL.path,
      selection: .paths([project.fileURL(for: "One.swift").path])
    )
    let missing = try await SourceCapture.capture(scope)
    try project.write("struct One {}", to: "One.swift")
    let present = try await SourceCapture.capture(scope)

    let records = reversingRecords ? [present, missing] : [missing, present]
    await #expect {
      try await SourceCapture.validate(records)
    } throws: { error in
      (error as? CaptureError)?.description
        .contains("snapshots disagree") == true
    }
  }

  @Test("Each validation reads current source")
  func separateValidationCalls() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App/One.swift": "struct One {}",
    ])
    let capture = try await SourceCapture.capture(scope(in: project))
    try await SourceCapture.validate([capture, capture])
    try project.write("struct ChangedOne {}", to: "Sources/App/One.swift")

    await #expect(throws: CaptureError.self) {
      try await SourceCapture.validate([capture, capture])
    }
  }

  private func scope(in project: TemporaryProject) -> SourceCapture.Scope {
    SourceCapture.Scope(
      rootPath: project.rootURL.path,
      selection: .sourceFiles(
        including: ["Sources/**"], excluding: ["**/Package.swift"],
        swiftPM: true, xcode: false
      )
    )
  }
}
