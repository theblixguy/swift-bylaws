import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Parse cache writing and reading")
struct ParseCacheTests {
  @Test("Cache key uses a stable SHA-256 digest")
  func stableCacheKey() {
    #expect(
      ParseCache.key(forSource: "class A {}")
        == "3b13dc89849e48e74f0090addc423484f98f428099fa868191da813183108c6b"
    )
  }

  @Test("A cache store and load returns every semantic field unchanged")
  func writingAndReadingPreservesParse() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = """
    public protocol Reloading {
      var state: Int { get }
      func reload() async -> Bool
    }

    final class HomeViewModel {
      init() {
        guard isReady else { return }
      }

      func reload() {
        if isReady { UserDefaults.standard.set(true, forKey: "seen") }
      }
    }
    """
    let path = "/App/HomeViewModel.swift"
    let parsed = try FileCollector.collect(source: source, path: path)

    await cache.store(parsed)
    let loaded = try #require(await cache.sourceFile(
      forSource: source,
      at: path
    ))
    #expect(cacheEntry(for: loaded) == cacheEntry(for: parsed))
    #expect(loaded.classes.first?.sourceText.hasPrefix("final class") == true)
    #expect(loaded.classes.first?.functions.map(\.name) == ["reload"])
    #expect(loaded.functions.first?.cyclomaticComplexity == 1)
    #expect(loaded.initializers.first?.cyclomaticComplexity == 1)
    let requirement = try #require(
      loaded.protocols.first?.requiredFunctions.first
    )
    #expect(requirement.sourceText == "func reload() async -> Bool")
    #expect(!requirement.sourceRange.isEmpty)
  }

  @Test("A cache store and load returns the file's line count unchanged")
  func writingAndReadingPreservesLineCount() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = "struct One {}\nstruct Two {}\r\nstruct Three {}\r"
    let path = "/App/Lines.swift"
    let parsed = try FileCollector.collect(source: source, path: path)

    await cache.store(parsed)
    let loaded = try #require(await cache.sourceFile(
      forSource: source,
      at: path
    ))

    #expect(parsed.lineCount == 4)
    #expect(loaded.lineCount == parsed.lineCount)
  }

  @Test("A changed source returns no cache entry")
  func missesOnChangedSource() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let path = "/App/A.swift"
    let parsed = try FileCollector.collect(source: "class A {}", path: path)

    await cache.store(parsed)
    #expect(await cache.sourceFile(forSource: "class B {}", at: path) == nil)
  }

  @Test("Moved source reuses cache with current path")
  func movedSource() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = "class A {}"
    let parsed = try FileCollector.collect(source: source, path: "/App/A.swift")

    await cache.store(parsed)
    let loaded = try #require(
      await cache.sourceFile(forSource: source, at: "/Lib/A.swift")
    )
    #expect(loaded.path == "/Lib/A.swift")
    #expect(loaded.classes.first?.location.filePath == "/Lib/A.swift")
  }

  @Test("A corrupt entry is replaced after a miss")
  func toleratesCorruptEntries() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = "class A {}"
    let path = "/App/A.swift"
    let entry = cache.directory.appendingPathComponent("corrupt-v11.pack")
    try Data("not an entry".utf8).write(to: entry)
    let reopened = try ParseCache.opening(directory: testCache.directory)

    #expect(await reopened.sourceFile(forSource: source, at: path) == nil)
    let parsed = try FileCollector.collect(source: source, path: path)
    await cache.store(parsed)
    let loaded = try #require(await cache.sourceFile(
      forSource: source,
      at: path
    ))
    #expect(cacheEntry(for: loaded) == cacheEntry(for: parsed))
  }

  @Test("A cache entry name does not exceed the 255-byte filesystem limit")
  func unicodeEntryNameFits() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = "struct Model {}"
    let path = "/App/\(String(repeating: "界", count: 64)).swift"
    let parsed = try FileCollector.collect(source: source, path: path)

    await cache.store(parsed)
    await cache.removeOldEntriesWhenDue()
    let entries = try FileManager.default.contentsOfDirectory(
      at: cache.directory, includingPropertiesForKeys: nil
    )

    #expect(entries.allSatisfy { $0.lastPathComponent.utf8.count <= 255 })
    #expect(await cache.sourceFile(forSource: source, at: path) != nil)
  }

  @Test("Cache ignores an entry whose source range exceeds the text")
  func toleratesInvalidRanges() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let source = "short"
    let path = "/App/A.swift"
    let sourceBuffer = SourceBuffer(source)
    let file = SourceFile(
      path: path,
      source: sourceBuffer,
      classes: [
        Class(
          storage: NominalTypeStorage(
            name: "A",
            inheritedTypes: [],
            source: sourceBuffer,
            sourceRange: 0..<99,
            visibility: .internal,
            location: DeclarationLocation.start(of: path)
          ),
          isFinal: false
        ),
      ]
    )

    await cache.store(file)
    #expect(await cache.sourceFile(forSource: source, at: path) == nil)
  }

  @Test(
    "A cache store and load returns the same data for every package source file"
  )
  func writingAndReadingPreservesEveryPackageFile() async throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    let root = URL(
      fileURLWithPath: try Codebase.automaticRoot(above: #filePath)
    )
    .appendingPathComponent("Sources")
    let files = try #require(
      FileManager.default.enumerator(atPath: root.path)
    )

    var swiftFileCount = 0
    var compared = 0
    while let relativePath = files.nextObject() as? String {
      guard relativePath.hasSuffix(".swift") else { continue }
      swiftFileCount += 1
      let path = root.appendingPathComponent(relativePath).path
      let source = try String(contentsOfFile: path, encoding: .utf8)
      let parsed = try FileCollector.collect(source: source, path: path)

      await cache.store(parsed)
      let loaded = try #require(await cache.sourceFile(
        forSource: source,
        at: path
      ))
      #expect(
        cacheEntry(for: loaded) == cacheEntry(for: parsed),
        "\(relativePath) changed after cache reading"
      )
      compared += 1
    }
    #expect(swiftFileCount > 50)
    #expect(compared == swiftFileCount)
  }

  private func cacheEntry(for file: SourceFile) -> [UInt8] {
    let encoder = CacheEncoder()
    encoder.encode(file)
    return encoder.bytes
  }
}
