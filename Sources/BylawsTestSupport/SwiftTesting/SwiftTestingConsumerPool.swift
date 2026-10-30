#if os(macOS) || os(Linux)
  package import Foundation

  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif

  package actor SwiftTestingConsumerPool {
    static let shared = SwiftTestingConsumerPool(under: sharedDirectory)
    private static let sharedDirectory: URL = {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "bylaws-consumers-\(UUID().uuidString)"
        )
      // Static pools do not release their projects when the process exits.
      atexit {
        try? FileManager.default.removeItem(at: sharedDirectory)
      }
      return directory
    }()

    private let parentDirectory: URL
    private var projects: [TemporaryProject] = []

    package init(under parentDirectory: URL = FileManager.default
      .temporaryDirectory)
    {
      self.parentDirectory = parentDirectory
    }

    package func withScope(
      performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
      let project = try projects.popLast()
        ?? TemporaryProject(files: [:], under: parentDirectory)
      do {
        try await SwiftTestingConsumerScope.$current.withValue(
          SwiftTestingConsumerScope(project: project),
          operation: function
        )
      } catch {
        if (try? reset(project)) != nil { projects.append(project) }
        throw error
      }
      try reset(project)
      projects.append(project)
    }

    private func reset(_ project: TemporaryProject) throws {
      let manager = FileManager.default
      for file in try manager.contentsOfDirectory(
        at: project.rootURL, includingPropertiesForKeys: nil
      ) {
        switch file.lastPathComponent {
        case "Package.swift":
          break
        case ".build":
          guard try file.resourceValues(forKeys: [.isDirectoryKey])
            .isDirectory == true
          else { throw POSIXError(.ENOTDIR) }
          for output in try manager.contentsOfDirectory(
            at: file, includingPropertiesForKeys: nil
          ) where output.lastPathComponent.hasPrefix("bylaws") {
            try manager.removeItem(at: output)
          }
        default:
          try manager.removeItem(at: file)
        }
      }
    }
  }

  actor SwiftTestingConsumerScope {
    @TaskLocal static var current: SwiftTestingConsumerScope?
    private var project: TemporaryProject?

    init(project: TemporaryProject) {
      self.project = project
    }

    func takeProject() -> TemporaryProject? {
      defer { project = nil }
      return project
    }
  }
#endif
