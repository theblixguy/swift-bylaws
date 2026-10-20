import BylawsTestSupport
import Foundation
import Testing
@testable import BylawsRunner
#if canImport(System)
  import System
#else
  import SystemPackage
#endif

@Suite("Correction staging")
struct CorrectionStagingTests {
  @Test(
    "Partial write failure removes owned temporary file",
    arguments: [Errno.noSpace, Errno.fileTooLarge]
  )
  func partialWrite(failure: Errno) throws {
    let project = try TemporaryProject(files: [
      "App.swift": "let value = 1\n",
      ".bylaws-existing.tmp": "keep\n",
    ])
    let destination = project.fileURL(for: "App.swift")
    var temporary: URL?

    #expect(throws: failure) {
      _ = try CorrectionPlan
        .stageTemporaryFile(beside: destination) { descriptor in
          try descriptor.writeAll(Data("part".utf8))
          let files = try FileManager.default.contentsOfDirectory(
            at: project.rootURL, includingPropertiesForKeys: nil
          )
          let created = files.filter {
            $0.lastPathComponent != "App.swift"
              && $0.lastPathComponent != ".bylaws-existing.tmp"
          }
          try #require(created.count == 1)
          let file = try #require(created.first)
          #expect(try Data(contentsOf: file) == Data("part".utf8))
          temporary = file
          throw failure
        }
    }

    let owned = try #require(temporary)
    #expect(!FileManager.default.fileExists(atPath: owned.path))
    let remaining = try FileManager.default.contentsOfDirectory(
      atPath: project.rootURL.path
    )
    #expect(remaining.sorted() == [".bylaws-existing.tmp", "App.swift"])
    #expect(try Data(contentsOf: destination) == Data("let value = 1\n".utf8))
    #expect(try Data(contentsOf: project.fileURL(for: ".bylaws-existing.tmp"))
      == Data("keep\n".utf8))
  }

  @Test("Successful staging retains complete sibling for replacement")
  func completeWrite() throws {
    let project = try TemporaryProject(files: ["App.swift": "let value = 1\n"])
    let destination = project.fileURL(for: "App.swift")

    let temporary = try CorrectionPlan.stageTemporaryFile(
      beside: destination
    ) { descriptor in
      try descriptor.writeAll(Data("let value = 2\n".utf8))
    }

    #expect(temporary.deletingLastPathComponent().path == project.rootURL.path)
    #expect(try Data(contentsOf: temporary) == Data("let value = 2\n".utf8))
    #expect(try Data(contentsOf: destination) == Data("let value = 1\n".utf8))
  }
}
