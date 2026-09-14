import BylawsCore
import BylawsSemantics
import Foundation
import Testing

@Suite("Parse cache writing and reading")
struct ParseCacheTests {
  @Test("Cache key uses a stable SHA-256 digest")
  func stableCacheKey() {
    #expect(
      ParseCache.key(forSource: "class A {}", at: "/App/A.swift")
        == "8ede1d21ad8f69f2f2fc1e35549b674960491faa0762df9ba0c60c0e1b70410a"
    )
  }

  @Test("A cache store and load returns every semantic field unchanged")
  func writingAndReadingPreservesParse() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
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

    cache.store(parsed, forSource: source, at: path)
    let loaded = try #require(cache.sourceFile(forSource: source, at: path))
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
  func writingAndReadingPreservesLineCount() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
    let source = "struct One {}\nstruct Two {}\r\nstruct Three {}\r"
    let path = "/App/Lines.swift"
    let parsed = try FileCollector.collect(source: source, path: path)

    cache.store(parsed, forSource: source, at: path)
    let loaded = try #require(cache.sourceFile(forSource: source, at: path))

    #expect(parsed.lineCount == 4)
    #expect(loaded.lineCount == parsed.lineCount)
  }

  @Test("A changed source returns no cache entry")
  func missesOnChangedSource() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
    let path = "/App/A.swift"
    let parsed = try FileCollector.collect(source: "class A {}", path: path)

    cache.store(parsed, forSource: "class A {}", at: path)
    #expect(cache.sourceFile(forSource: "class B {}", at: path) == nil)
  }

  @Test("The same source at another path returns no cache entry")
  func missesOnChangedPath() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
    let source = "class A {}"
    let parsed = try FileCollector.collect(source: source, path: "/App/A.swift")

    cache.store(parsed, forSource: source, at: "/App/A.swift")
    #expect(cache.sourceFile(forSource: source, at: "/Lib/A.swift") == nil)
  }

  @Test("A corrupt entry is replaced after a miss")
  func toleratesCorruptEntries() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
    let source = "class A {}"
    let path = "/App/A.swift"
    let entry = cache.entry(forSource: source, at: path)
    try Data("not an entry".utf8).write(to: entry)

    #expect(cache.sourceFile(forSource: source, at: path) == nil)
    let parsed = try FileCollector.collect(source: source, path: path)
    cache.store(parsed, forSource: source, at: path)
    let loaded = try #require(cache.sourceFile(forSource: source, at: path))
    #expect(cacheEntry(for: loaded) == cacheEntry(for: parsed))
  }

  @Test("A project-scoped cache stores entries in the project's directory")
  func scopesEntriesByProject() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = try testCache.cache.opening(project: "MyApp")
    defer { withExtendedLifetime(testCache) {} }
    let entry = cache.entry(
      forSource: "class A {}",
      at: "/repo/MyApp/Sources/A.swift"
    )
    #expect(entry.pathComponents.contains("MyApp"))
    #expect(entry.lastPathComponent.hasPrefix("A-"))
    #expect(entry.lastPathComponent.hasSuffix(".bin"))
  }

  @Test("A cache entry name does not exceed the 255-byte filesystem limit")
  func unicodeEntryNameFits() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
    let source = "struct Model {}"
    let path = "/App/\(String(repeating: "界", count: 64)).swift"
    let entry = cache.entry(forSource: source, at: path)
    let parsed = try FileCollector.collect(source: source, path: path)

    cache.store(parsed, forSource: source, at: path)

    #expect(entry.lastPathComponent.utf8.count <= 255)
    #expect(cache.sourceFile(forSource: source, at: path) != nil)
  }

  @Test("Cache ignores an entry whose source range exceeds the text")
  func toleratesInvalidRanges() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
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

    cache.store(file, forSource: source, at: path)
    #expect(cache.sourceFile(forSource: source, at: path) == nil)
  }

  @Test(
    "A cache store and load returns the same data for every package source file"
  )
  func writingAndReadingPreservesEveryPackageFile() throws {
    let testCache = try ParseCacheTestStorage()
    let cache = testCache.cache
    defer { withExtendedLifetime(testCache) {} }
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

      cache.store(parsed, forSource: source, at: path)
      let loaded = try #require(cache.sourceFile(forSource: source, at: path))
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
