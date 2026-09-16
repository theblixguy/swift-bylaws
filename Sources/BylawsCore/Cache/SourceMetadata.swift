import Foundation
import SystemPackage

struct SourceMetadata: Codable, Equatable, Sendable {
  struct Timestamp: Codable, Equatable, Sendable {
    let seconds: Int64
    let nanoseconds: Int64

    func isReliable(before cutoff: TimeInterval) -> Bool {
      seconds > 0 && nanoseconds > 0 && nanoseconds < 1_000_000_000
        && Double(seconds) + Double(nanoseconds) / 1_000_000_000 < cutoff
    }
  }

  let device: UInt64
  let inode: UInt64
  let size: Int64
  let modified: Timestamp
  let changed: Timestamp

  static func read(at path: String) -> Self? {
    guard let status = try? FilePath(path).stat(followTargetSymlink: true),
          status.type == .regular, status.size >= 0, status.inode.rawValue != 0
    else { return nil }
    return Self(
      device: UInt64(truncatingIfNeeded: status.deviceID.rawValue),
      inode: UInt64(status.inode.rawValue),
      size: status.size,
      modified: Timestamp(
        seconds: Int64(status.st_mtim.tv_sec),
        nanoseconds: Int64(status.st_mtim.tv_nsec)
      ),
      changed: Timestamp(
        seconds: Int64(status.st_ctim.tv_sec),
        nanoseconds: Int64(status.st_ctim.tv_nsec)
      )
    )
  }

  func canReuse(at date: Date) -> Bool {
    // A recent timestamp can share a filesystem clock interval with a later edit.
    let cutoff = date.timeIntervalSince1970 - 2
    return modified.isReliable(before: cutoff)
      && changed.isReliable(before: cutoff)
  }
}
