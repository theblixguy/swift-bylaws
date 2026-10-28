#if os(macOS) || os(Linux)
  import BylawsTestSupport
  import Foundation
  import Testing

  @Suite("Swift Testing consumer builds")
  struct SwiftTestingConsumerPoolTests {
    @Test(
      "Parameterized consumers receive separate test inputs",
      .reuseSwiftTestingBuild, arguments: [0, 1, 2]
    )
    func parameterizedConsumers(_ value: Int) async throws {
      let consumer = try await SwiftTestingReportConsumer()
      let source = "class Screen\(value) {}\n"
      try consumer.writeSource(source)

      #expect(consumer.root.deletingLastPathComponent().lastPathComponent
        .hasPrefix("bylaws-consumers-"))
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
        == source)
    }

    @Test("Build trait scopes consumer inputs", .reuseSwiftTestingBuild)
    func scopedConsumer() async throws {
      let consumer = try await SwiftTestingReportConsumer()
      #expect(consumer.root.deletingLastPathComponent().lastPathComponent
        .hasPrefix("bylaws-consumers-"))
      #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
        == SwiftTestingReportConsumer.source)
    }

    @Test("Reused consumer keeps build files and resets source and reports")
    func resetConsumer() async throws {
      let pool = SwiftTestingConsumerPool()
      let roots = ConsumerRoots()
      try await pool.withScope {
        let consumer = try await SwiftTestingReportConsumer(
          additionalTests: "func previousRule() {}"
        )
        await roots.append(consumer.root)
        try consumer.writeSource("class Changed {}\n")
        for path in [
          "Sources/App/Previous.swift", "Package.resolved", "previous.json",
          ".build/debug/dependency.o",
          ".build/bylaws-reporting-old/report.json",
        ] {
          let file = consumer.root.appendingPathComponent(path)
          try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try Data("previous".utf8).write(to: file)
        }
        try FileManager.default.setAttributes(
          [.modificationDate: Date(timeIntervalSince1970: 1000)],
          ofItemAtPath: consumer.root.appendingPathComponent("Package.swift")
            .path
        )
      }

      try await pool.withScope {
        let consumer = try await SwiftTestingReportConsumer()
        let previousRoot = await roots.values.first
        #expect(consumer.root == previousRoot)
        #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
        for path in [
          "Sources/App/Previous.swift", "Package.resolved", "previous.json",
          ".build/bylaws-reporting-old",
        ] {
          #expect(!FileManager.default.fileExists(
            atPath: consumer.root.appendingPathComponent(path).path
          ))
        }
        #expect(try String(
          contentsOf: consumer.root
            .appendingPathComponent(".build/debug/dependency.o"),
          encoding: .utf8
        ) == "previous")
        let rules = try String(
          contentsOf: consumer.root
            .appendingPathComponent("Tests/RuleTests/Rules.swift"),
          encoding: .utf8
        )
        #expect(!rules.contains("previousRule"))
        let attributes = try FileManager.default.attributesOfItem(
          atPath: consumer.root.appendingPathComponent("Package.swift").path
        )
        #expect(attributes[.modificationDate] as? Date
          == Date(timeIntervalSince1970: 1000))
      }
    }

    @Test("Overlapping scopes use separate consumer roots")
    func overlappingScopes() async throws {
      let pool = SwiftTestingConsumerPool()
      try await pool.withScope {
        let first = try await SwiftTestingReportConsumer()
        try first.writeSource("class First {}\n")
        try await pool.withScope {
          let second = try await SwiftTestingReportConsumer()
          #expect(first.root != second.root)
          try second.writeSource("class Second {}\n")
          #expect(try String(contentsOf: first.sourceFile, encoding: .utf8)
            == "class First {}\n")
        }
        #expect(try String(contentsOf: first.sourceFile, encoding: .utf8)
          == "class First {}\n")
      }
    }

    @Test("Additional consumer in scope has separate source and build files")
    func additionalConsumer() async throws {
      let pool = SwiftTestingConsumerPool()
      try await pool.withScope {
        let first = try await SwiftTestingReportConsumer()
        let second = try await SwiftTestingReportConsumer()
        #expect(first.root != second.root)
        try first.writeSource("class First {}\n")
        #expect(try String(contentsOf: second.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
      }
    }

    @Test("Thrown scope resets consumer before reuse")
    func thrownScope() async throws {
      let pool = SwiftTestingConsumerPool()
      let roots = ConsumerRoots()
      await #expect(throws: MockError.failed) {
        try await pool.withScope {
          let consumer = try await SwiftTestingReportConsumer()
          await roots.append(consumer.root)
          try consumer.writeSource("class Changed {}\n")
          throw MockError.failed
        }
      }

      try await pool.withScope {
        let consumer = try await SwiftTestingReportConsumer()
        let previousRoot = await roots.values.first
        #expect(consumer.root == previousRoot)
        #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
      }
    }

    @Test("Cleanup failure discards consumer")
    func failedCleanup() async throws {
      let pool = SwiftTestingConsumerPool()
      let roots = ConsumerRoots()
      await #expect(throws: (any Error).self) {
        try await pool.withScope {
          let consumer = try await SwiftTestingReportConsumer()
          await roots.append(consumer.root)
          try Data("file instead of build directory".utf8).write(
            to: consumer.root.appendingPathComponent(".build")
          )
        }
      }

      try await pool.withScope {
        let consumer = try await SwiftTestingReportConsumer()
        let previousRoot = await roots.values.first
        #expect(consumer.root != previousRoot)
        #expect(try String(contentsOf: consumer.sourceFile, encoding: .utf8)
          == SwiftTestingReportConsumer.source)
      }
    }

    private actor ConsumerRoots {
      var values: [URL] = []

      func append(_ root: URL) {
        values.append(root)
      }
    }

    private enum MockError: Error {
      case failed
    }
  }
#endif
