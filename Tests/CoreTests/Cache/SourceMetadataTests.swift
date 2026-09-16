import Foundation
import Testing
@testable import BylawsCore

@Suite("Source metadata timestamps")
struct SourceMetadataTests {
  @Test(
    "Recent, future and coarse timestamps require content validation",
    arguments: [
      (98, 1), (100, 1), (101, 1), (97, 0), (0, 1), (97, -1), (
        97,
        1_000_000_000
      ),
    ]
  )
  func uncertainTimestamp(seconds: Int64, nanoseconds: Int64) {
    let timestamp = SourceMetadata.Timestamp(
      seconds: seconds,
      nanoseconds: nanoseconds
    )
    let stable = SourceMetadata.Timestamp(seconds: 95, nanoseconds: 1)
    let now = Date(timeIntervalSince1970: 100)
    let modified = SourceMetadata(
      device: 1,
      inode: 1,
      size: 1,
      modified: timestamp,
      changed: stable
    )
    let changed = SourceMetadata(
      device: 1,
      inode: 1,
      size: 1,
      modified: stable,
      changed: timestamp
    )

    #expect(!modified.canReuse(at: now))
    #expect(!changed.canReuse(at: now))
  }

  @Test("Precise timestamps before the safety interval permit reuse")
  func stableTimestamp() {
    let timestamp = SourceMetadata.Timestamp(
      seconds: 97,
      nanoseconds: 999_999_999
    )
    let metadata = SourceMetadata(
      device: 1,
      inode: 1,
      size: 1,
      modified: timestamp,
      changed: timestamp
    )

    #expect(metadata.canReuse(at: Date(timeIntervalSince1970: 100)))
  }
}
