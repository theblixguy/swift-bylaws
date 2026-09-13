import Bylaws
import Foundation
import Testing

@Suite("Unreadable sources")
struct UnreadableSourceTests {
  @Test("A file that is not UTF-8 fails the query")
  func invalidTextFailsTheQuery() async throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let path = "\(root)/Sources/Invalid.swift"
    try Data([0xFF, 0xFE, 0x00]).write(to: URL(fileURLWithPath: path))
    await #expect {
      try await Codebase(root: .directory(root)).structs
    } throws: { error in
      guard let error = error as? CodebaseError else { return false }
      guard case let .unreadable(failures) = error else { return false }
      return failures == [
        .init(path: path, reason: "the file is not UTF-8 text"),
      ]
        && error.description == """
        Bylaws cannot read '\(path)': the file is not UTF-8 text. \
        A query needs every file under the root.
        """
    }
  }

  @Test(
    "A query fails when the file walk cannot open a directory",
    .enabled(if: getuid() != 0, "Root can read a directory with mode 000.")
  )
  func unopenableDirectoryFailsTheQuery() async throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let manager = FileManager.default
    let directory = "\(root)/Sources/Private"
    try manager.createDirectory(
      atPath: directory,
      withIntermediateDirectories: true
    )
    try "struct Hidden {}".write(
      toFile: "\(directory)/Hidden.swift",
      atomically: true,
      encoding: .utf8
    )
    try manager.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: directory
    )
    defer {
      try? manager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: directory
      )
    }

    await #expect {
      try await Codebase(root: .directory(root)).structs
    } throws: { error in
      guard let error = error as? CodebaseError else { return false }
      guard case let .unreadable(failures) = error else { return false }
      return failures.map(\.path) == [directory]
    }
  }

  @Test(
    "Automatic root discovery reports an unreadable directory",
    .enabled(if: getuid() != 0, "Root can read a directory with mode 000.")
  )
  func unopenableDirectoryFailsRootDiscovery() throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let manager = FileManager.default
    let directory = "\(root)/Private"
    try manager.createDirectory(
      atPath: directory,
      withIntermediateDirectories: true
    )
    try manager.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: directory
    )
    defer {
      try? manager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: directory
      )
    }

    #expect {
      try Codebase.automaticRoot(above: "\(directory)/Rules.swift")
    } throws: { error in
      guard let error = error as? CodebaseError else { return false }
      guard case let .unreadable(failures) = error else { return false }
      return failures.map(\.path) == [directory]
    }
  }

  @Test(
    "An include glob skips an unreadable unrelated directory",
    .enabled(if: getuid() != 0, "Root can read a directory with mode 000.")
  )
  func includeSkipsUnopenableUnrelatedDirectory() async throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let manager = FileManager.default
    let directory = "\(root)/Vendor/Private"
    try manager.createDirectory(
      atPath: directory,
      withIntermediateDirectories: true
    )
    try "struct Hidden {}".write(
      toFile: "\(directory)/Hidden.swift",
      atomically: true,
      encoding: .utf8
    )
    try manager.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: directory
    )
    defer {
      try? manager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: directory
      )
    }

    let structs = try await Codebase(
      root: .directory(root),
      including: ["Sources/**"]
    ).structs

    #expect(structs.map(\.name) == ["Readable"])
  }

  @Test("A query succeeds for a readable directory tree")
  func readableTreeAnswersTheQuery() async throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let structs = try await Codebase(root: .directory(root)).structs
    #expect(structs.map(\.name) == ["Readable"])
  }

  @Test("File walk skips a symbolic link directory")
  func symbolicLinkDirectoryIsSkipped() async throws {
    let root = try makeReadableRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let manager = FileManager.default
    let destination = NSTemporaryDirectory()
      + "bylaws-linked-directory-\(UUID().uuidString)"
    try manager.createDirectory(
      atPath: destination,
      withIntermediateDirectories: true
    )
    defer { try? manager.removeItem(atPath: destination) }
    try "struct Linked {}".write(
      toFile: "\(destination)/Linked.swift",
      atomically: true,
      encoding: .utf8
    )
    try manager.createSymbolicLink(
      atPath: "\(root)/Sources/Linked",
      withDestinationPath: destination
    )

    let structs = try await Codebase(root: .directory(root)).structs

    #expect(structs.map(\.name) == ["Readable"])
  }
}

private func makeReadableRoot() throws -> String {
  let root = NSTemporaryDirectory() + "bylaws-unreadable-\(UUID().uuidString)"
  try FileManager.default.createDirectory(
    atPath: "\(root)/Sources",
    withIntermediateDirectories: true
  )
  try "struct Readable {}".write(
    toFile: "\(root)/Sources/Readable.swift",
    atomically: true,
    encoding: .utf8
  )
  return root
}
