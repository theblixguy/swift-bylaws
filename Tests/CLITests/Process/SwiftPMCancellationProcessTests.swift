#if os(macOS) || os(Linux)
  import BylawsTestSupport
  import Foundation
  import Subprocess
  import Testing
  @testable import BylawsRunner

  #if canImport(System)
    import System
  #else
    import SystemPackage
  #endif

  #if canImport(Darwin)
    import Darwin
  #else
    import Glibc
  #endif

  @Suite("SwiftPM build cancellation")
  struct SwiftPMCancellationProcessTests {
    @Test(
      "Cancellation interrupts build tool in separate process group",
      .timeLimit(.minutes(2))
    )
    func buildToolCancellation() async throws {
      let project = try project()
      let eventsFile = project.fileURL(for: "events")
      let fifoStatus = unsafe mkfifo(eventsFile.path, 0o600)
      try #require(fifoStatus == 0)
      let (events, eventContinuation) =
        AsyncThrowingStream<String, any Error>.makeStream()
      let (started, startContinuation) = AsyncStream<Int32>.makeStream()

      try await withThrowingTaskGroup(of: Void.self) { readers in
        readers.addTask {
          do {
            let result = try await Subprocess.run(
              .path("/bin/cat"), arguments: [eventsFile.path],
              input: .none, output: .sequence, error: .discarded
            ) { execution in
              for try await line in execution.standardOutput.strings() {
                eventContinuation.yield(line)
              }
            }
            #expect(result.terminationStatus == .exited(0))
            eventContinuation.finish()
          } catch {
            eventContinuation.finish(throwing: error)
            throw error
          }
        }
        defer { readers.cancelAll() }

        try await withThrowingTaskGroup(of: Void.self) { commands in
          commands.addTask {
            defer { startContinuation.finish() }
            do {
              let result = try await SwiftPMCommand.run(
                arguments: ["build", "--disable-sandbox", "--target", "App"],
                rootPath: project.rootURL.path,
                directory: project.rootURL,
                environment: SwiftPMTestRunner.subprocessEnvironment(),
                onStart: { startContinuation.yield($0) }
              )
              throw CompletedBuild(result: result)
            } catch {
              if !Task.isCancelled {
                eventContinuation.finish(throwing: error)
              }
              throw error
            }
          }
          defer { commands.cancelAll() }

          var iterator = events.makeAsyncIterator()
          let firstEvent = try await iterator.next()
          if firstEvent == nil {
            try await commands.waitForAll()
          }
          let ready = try #require(firstEvent)
          let identifiers = ready.split(separator: " ").compactMap { Int32($0) }
          try #require(identifiers.count == 2)
          let toolPID = identifiers[0]
          let toolGroup = identifiers[1]
          try #require(toolPID > 0 && toolGroup == toolPID)
          var toolStopped = false
          defer {
            if !toolStopped {
              _ = kill(-toolGroup, SIGKILL)
            }
          }
          let commandPID = try #require(await started.first { _ in true })
          let commandGroup = getpgid(commandPID)
          try #require(commandGroup > 0)
          #expect(commandGroup == getpgrp())
          #expect(toolGroup != commandGroup)

          commands.cancelAll()
          try await #require(throws: CancellationError.self) {
            try await commands.waitForAll()
          }
          #expect(try await iterator.next() == "interrupted")
          let end = try await iterator.next()
          try #require(end == nil)
          toolStopped = true
        }
        try await readers.waitForAll()
      }
    }

    private struct CompletedBuild: Error, CustomStringConvertible {
      let result: SwiftPMCommand.Result

      var description: String {
        """
        SwiftPM completed before cancellation: \(result.terminationStatus)
        \(String(decoding: result.standardOutput, as: UTF8.self))
        \(String(decoding: result.standardError, as: UTF8.self))
        """
      }
    }

    private func project() throws -> TemporaryProject {
      try TemporaryProject(files: [
        "Package.swift": """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
          name: "BuildCancellationMock",
          platforms: [.macOS(.v14)],
          targets: [
            .target(name: "App", plugins: ["HoldPlugin"]),
            .executableTarget(name: "HoldTool"),
            .plugin(
              name: "HoldPlugin", capability: .buildTool(),
              dependencies: ["HoldTool"]
            )
          ]
        )
        """,
        "Sources/App/App.swift": "public struct App {}",
        "Plugins/HoldPlugin/Plugin.swift": """
        import Foundation
        import PackagePlugin

        @main struct HoldPlugin: BuildToolPlugin {
          func createBuildCommands(
            context: PluginContext, target: any Target
          ) async throws -> [Command] {
            let tool = try context.tool(named: "HoldTool")
            return [.buildCommand(
              displayName: "Wait for interrupt",
              executable: tool.url,
              arguments: [context.package.directoryURL
                .appendingPathComponent("events").path],
              outputFiles: [context.pluginWorkDirectoryURL
                .appendingPathComponent("output")]
            )]
          }
        }
        """,
        "Sources/HoldTool/HoldTool.swift": #"""
        import Dispatch
        import Foundation

        #if canImport(Darwin)
        import Darwin
        #else
        import Glibc
        #endif

        @main struct HoldTool {
          static func main() async throws {
            let descriptor = open(CommandLine.arguments[1], O_WRONLY | O_CLOEXEC)
            guard descriptor >= 0 else {
              throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            // EOF must mean that the tool has exited.
            let events = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            signal(SIGINT, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
              signal: SIGINT, queue: .global()
            )
            let (interrupts, continuation) = AsyncStream<Void>.makeStream()
            source.setEventHandler { @Sendable in
              continuation.yield(())
              continuation.finish()
            }
            await withCheckedContinuation { (registered: CheckedContinuation<Void, Never>) in
              source.setRegistrationHandler { @Sendable in registered.resume() }
              source.activate()
            }
            defer { source.cancel() }
            try events.write(contentsOf: Data("\(getpid()) \(getpgrp())\n".utf8))
            for await _ in interrupts { break }
            try events.write(contentsOf: Data("interrupted\n".utf8))
          }
        }
        """#,
      ])
    }
  }
#endif
