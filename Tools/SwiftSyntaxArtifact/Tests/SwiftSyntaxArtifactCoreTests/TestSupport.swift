import Foundation

func withTemporaryDirectory<Result>(
  _ body: (URL) throws -> Result
) throws -> Result {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}
