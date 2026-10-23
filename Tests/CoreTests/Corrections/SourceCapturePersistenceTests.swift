import BylawsSemantics
import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsCore

@Suite("Source capture persistence")
struct SourceCapturePersistenceTests {
  @Test("Stored query record preserves source bytes and session")
  func storedRecord() async throws {
    let project = try TemporaryProject(files: [
      "Sources/App.swift": "struct App {}\n",
    ])
    let output = try TemporaryProject(files: [:])
    let codebase = Codebase(
      root: .directory(project.rootURL.path), including: ["Sources/**"],
      swiftLanguageMode: .v6
    )
    let collector = SourceCapture.Collector()
    let structs = try await SourceCapture.$collector.withValue(collector) {
      try await codebase.structs
    }
    #expect(structs.map(\.name) == ["App"])
    let captured = await collector.captured
    try #require(captured.count == 1)
    let observed = try #require(captured.first)
    let record = SourceCapture.Record(
      sessionID: "persistence-session", scope: observed.scope,
      inputs: observed.inputs, sourcePaths: observed.sourcePaths,
      rootSearchPath: observed.rootSearchPath,
      directories: observed.directories,
      unavailableReason: observed.unavailableReason
    )

    try await SourceCapture.store(record, environment: [
      "BYLAWS_SOURCE_CAPTURE_DIRECTORY": output.rootURL.path,
      "BYLAWS_SOURCE_CAPTURE_ID": "persistence-session",
    ])

    let files = try FileManager.default.contentsOfDirectory(
      at: output.rootURL, includingPropertiesForKeys: nil
    )
    try #require(files.count == 1)
    let file = try #require(files.first)
    #expect(file.pathExtension == "json")
    let stored = try JSONDecoder().decode(
      SourceCapture.Record.self, from: Data(contentsOf: file)
    )
    let sourcePath = project.fileURL(for: "Sources/App.swift").path
    #expect(stored.sessionID == "persistence-session")
    #expect(stored.scope.rootPath == project.rootURL.path)
    #expect(stored.sourcePaths == [sourcePath])
    #expect(stored.inputs.map(\.path) == [sourcePath])
    #expect(stored.inputs.map(\.digest) == [
      "4e9ef75d569906e953155df5a4666c5015b61d56a137d4da28653847daee94a6",
    ])
    #expect(stored.unavailableReason == nil)
    try await SourceCapture.validate([stored])
  }

  @Test("Disk capture without session reports missing session")
  func missingSession() async throws {
    let output = try TemporaryProject(files: [:])
    let record = SourceCapture.Record(
      sessionID: nil,
      scope: .init(
        rootPath: output.rootURL.path,
        selection: .sourceFiles(
          including: [], excluding: [], swiftPM: false, xcode: false
        )
      ),
      inputs: []
    )

    await #expect {
      try await SourceCapture.store(record, environment: [
        "BYLAWS_SOURCE_CAPTURE_DIRECTORY": output.rootURL.path,
      ])
    } throws: { error in
      (error as? CaptureError)?.description
        == "the source capture session is missing"
    }
    let files = try FileManager.default.contentsOfDirectory(
      atPath: output.rootURL.path
    )
    #expect(files.isEmpty)
  }

  @Test("File used as capture directory reports write failure")
  func unusableDirectory() async throws {
    let project = try TemporaryProject(files: ["captures": "keep"])
    let record = SourceCapture.Record(
      sessionID: "persistence-session",
      scope: .init(
        rootPath: project.rootURL.path,
        selection: .sourceFiles(
          including: [], excluding: [], swiftPM: false, xcode: false
        )
      ),
      inputs: []
    )

    await #expect {
      try await SourceCapture.store(record, environment: [
        "BYLAWS_SOURCE_CAPTURE_DIRECTORY": project.fileURL(for: "captures")
          .path,
      ])
    } throws: { error in
      (error as NSError).domain == NSCocoaErrorDomain
    }
    let contents = try String(
      contentsOf: project.fileURL(for: "captures"), encoding: .utf8
    )
    #expect(contents == "keep")
  }

  @Test("Failed query and capture write retain both causes")
  func failedQueryStorage() async throws {
    let project = try TemporaryProject(files: ["captures": "keep"])
    let outputPath = project.fileURL(for: "captures").path
    let queryReason = "cannot read Sources/App.swift: source bytes changed"
    let record = SourceCapture.Record(
      sessionID: "persistence-session",
      scope: .init(
        rootPath: project.rootURL.path,
        selection: .sourceFiles(
          including: [], excluding: [], swiftPM: false, xcode: false
        )
      ),
      inputs: [], unavailableReason: queryReason
    )

    await #expect {
      try await SourceCapture.save(record, environment: [
        "BYLAWS_SOURCE_CAPTURE_DIRECTORY": outputPath,
      ])
    } throws: { error in
      guard let error = error as? CodebaseError,
            case let .unreadable(failures) = error,
            failures.count == 1, let failure = failures.first
      else { return false }
      return failure.path == project.rootURL.path
        && failure.reason.contains(queryReason)
        && failure.reason.contains("cannot save the source capture:")
        && failure.reason.contains(outputPath)
    }
  }
}
