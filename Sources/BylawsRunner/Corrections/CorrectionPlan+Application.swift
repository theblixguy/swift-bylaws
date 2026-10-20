package import BylawsCore
import Foundation

#if canImport(Darwin)
  import Darwin
#else
  import Glibc
#endif

#if canImport(System)
  import System
#else
  import SystemPackage
#endif

extension CorrectionPlan {
  package struct ApplicationError: Error, CustomStringConvertible {
    package let changedPaths: [String]
    package let failedPath: String
    package let reason: String

    package var description: String {
      let changed = changedPaths.isEmpty
        ? "No files changed."
        : "Changed files: \(changedPaths.joined(separator: ", "))."
      return "cannot apply the correction at '\(failedPath)': \(reason)\n\(changed)"
    }
  }

  package func apply(captures: [SourceCapture.Record]) async throws
    -> [String]
  {
    try await SourceCapture.validate(captures)
    var staged: [(change: Change, temporary: URL)] = []
    var changed: [String] = []
    defer {
      for item in staged {
        try? FileManager.default.removeItem(at: item.temporary)
      }
    }
    for change in changes {
      do {
        try Task.checkCancellation()
        let destination = URL(fileURLWithPath: change.path)
        let attributes = try FileManager.default
          .attributesOfItem(atPath: change.path)
        let temporary = try Self
          .stageTemporaryFile(beside: destination) { writer in
            try writer.writeAll(change.replacement)
          }
        staged.append((change, temporary))
        if let permissions = attributes[.posixPermissions] {
          try FileManager.default.setAttributes(
            [.posixPermissions: permissions], ofItemAtPath: temporary.path
          )
        }
      } catch {
        throw ApplicationError(
          changedPaths: [], failedPath: change.path,
          reason: String(describing: error)
        )
      }
    }
    try await SourceCapture.validate(captures)
    for item in staged {
      do {
        try Task.checkCancellation()
        let destination = URL(fileURLWithPath: item.change.path)
        let attributes = try FileManager.default.attributesOfItem(
          atPath: item.change.path
        )
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
              destination.resolvingSymlinksInPath().path == item.change
                .resolvedPath,
              try Data(contentsOf: destination) == item.change.original
        else {
          throw CaptureError(
            "the source changed before replacement. Run the command again."
          )
        }
        guard unsafe rename(item.temporary.path, item.change.path) == 0 else {
          throw Errno(rawValue: errno)
        }
        changed.append(item.change.path)
      } catch {
        throw ApplicationError(
          changedPaths: changed, failedPath: item.change.path,
          reason: String(describing: error)
        )
      }
    }
    return changed
  }

  static func stageTemporaryFile(
    beside destination: URL, write: (FileDescriptor) throws -> Void
  ) throws -> URL {
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".bylaws-\(UUID().uuidString).tmp")
    let descriptor = try FileDescriptor.open(
      FilePath(temporary.path), .writeOnly,
      options: [.create, .exclusiveCreate, .closeOnExec],
      permissions: .ownerReadWrite
    )
    do {
      try descriptor.closeAfter {
        try write(descriptor)
        if try descriptor.seek(offset: 0, from: .end) > 0 {
          try FileHandle(
            fileDescriptor: descriptor.rawValue, closeOnDealloc: false
          ).synchronize()
        }
      }
      return temporary
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw error
    }
  }
}
