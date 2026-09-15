import BylawsTestSupport
import Foundation
import Testing

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite("LSP process transport")
struct TransportTests {
  @Test("Server completes initialise and shutdown exchange")
  func lifecycle() async throws {
    let server = try LanguageServerSession()

    let initializeResponse = try await server.initialize()
    #expect(initializeResponse.id == 1)
    let initializeResult = try #require(initializeResponse.result)
    #expect(initializeResult.capabilities.hasTextDocumentSync)

    let shutdownResponse = try await server.shutdown()
    #expect(shutdownResponse.id == 2)
    try await server.exit()
    try await server.waitUntilExit()

    let status = await server.status
    let standardError = await server.standardError
    #expect(status == 0)
    #expect(standardError.isEmpty)
  }

  @Test("Exit without shutdown returns status code 1")
  func exitWithoutShutdown() async throws {
    let server = try LanguageServerSession()
    _ = try await server.initialize()

    try await server.exit()
    try await server.waitUntilExit()

    let status = await server.status
    let standardError = await server.standardError
    #expect(status == 1)
    #expect(standardError.isEmpty)
  }

  @Test("Input closure ends server", arguments: [false, true])
  func inputClosure(initializeBeforeClosing: Bool) async throws {
    let server = try LanguageServerSession()
    if initializeBeforeClosing {
      _ = try await server.initialize()
    }

    try await server.closeInput()
    try await server.waitUntilExit()

    let status = await server.status
    let standardError = await server.standardError
    #expect(status == 0)
    #expect(standardError.isEmpty)
  }
}

private actor LanguageServerSession {
  private static let timeout = Duration.seconds(5)

  private let error = Pipe()
  private let input = Pipe()
  private let output = Pipe()
  private let process = Process()
  private let errorChunks: AsyncStream<Data>
  private let outputChunks: AsyncStream<Data>
  private let processExit: AsyncStream<Void>
  private var capturedError = Data()
  private var capturedOutput = Data()
  private var pendingOutput: ArraySlice<UInt8> = []

  var standardError: String {
    get async { String(decoding: await readStandardError(), as: UTF8.self) }
  }

  var status: Int32 { process.terminationStatus }

  init() throws {
    let (processExit, continuation) = AsyncStream<Void>.makeStream()
    self.processExit = processExit
    let (outputChunks, outputContinuation) = AsyncStream<Data>.makeStream()
    self.outputChunks = outputChunks
    let (errorChunks, errorContinuation) = AsyncStream<Data>.makeStream()
    self.errorChunks = errorChunks

    output.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        outputContinuation.finish()
        return
      }
      outputContinuation.yield(data)
    }
    error.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        errorContinuation.finish()
        return
      }
      errorContinuation.yield(data)
    }
    process.terminationHandler = { _ in
      continuation.yield()
      continuation.finish()
    }
    process.executableURL = try Self.executable()
    var environment = ProcessInfo.processInfo.environment
    environment["SOURCEKIT_LSP_LOG_LEVEL"] = "error"
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = error
    try process.run()
    input.fileHandleForReading.closeFile()
    output.fileHandleForWriting.closeFile()
    error.fileHandleForWriting.closeFile()
  }

  deinit {
    output.fileHandleForReading.readabilityHandler = nil
    error.fileHandleForReading.readabilityHandler = nil
    if process.isRunning {
      process.terminate()
    }
  }

  func initialize() async throws -> ServerResponse {
    try send([
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": [
        "processId": NSNull(),
        "rootUri": URL(fileURLWithPath: FileManager.default
          .currentDirectoryPath)
          .absoluteString,
        "capabilities": [:],
        "workspaceFolders": NSNull(),
      ],
    ])
    return try await readMessage(waitingFor: "the initialize response")
  }

  func shutdown() async throws -> ServerResponse {
    try send([
      "jsonrpc": "2.0",
      "id": 2,
      "method": "shutdown",
    ])
    return try await readMessage(waitingFor: "the shutdown response")
  }

  func exit() throws {
    try send(["jsonrpc": "2.0", "method": "exit"])
  }

  func closeInput() throws {
    try input.fileHandleForWriting.close()
  }

  func waitUntilExit() async throws {
    do {
      try await beforeTimeout {
        await self.waitForProcessExit()
      }
    } catch is DeadlineReached {
      terminate()
      await waitForProcessExit()
      throw await timeoutFailure(waitingFor: "bylaws-lsp to exit")
    }
  }

  private func send(_ message: [String: Any]) throws {
    let content = try JSONSerialization.data(withJSONObject: message)
    var framed = Data("Content-Length: \(content.count)\r\n\r\n".utf8)
    framed.append(content)
    try input.fileHandleForWriting.write(contentsOf: framed)
  }

  private func readMessage(
    waitingFor operation: String
  ) async throws -> ServerResponse {
    let content: Data
    do {
      content = try await beforeTimeout {
        try await self.readMessageData()
      }
    } catch is DeadlineReached {
      terminate()
      await waitForProcessExit()
      throw await timeoutFailure(waitingFor: operation)
    } catch is EndOfOutput {
      terminate()
      await waitForProcessExit()
      throw TransportFailure.unexpectedEndOfFile(await diagnostics())
    }
    return try JSONDecoder().decode(ServerResponse.self, from: content)
  }

  private func readMessageData() async throws -> Data {
    var header = Data()
    let delimiter = Data("\r\n\r\n".utf8)
    while header.count < delimiter.count
      || !header.suffix(delimiter.count).elementsEqual(delimiter)
    {
      let byte = try await readOutputByte()
      header.append(byte)
    }
    let headerText = String(decoding: header, as: UTF8.self)
    let lengthLine = try #require(
      headerText.components(separatedBy: "\r\n").first {
        $0.lowercased().hasPrefix("content-length:")
      }
    )
    let length = try #require(
      Int(lengthLine.split(separator: ":", maxSplits: 1)[1]
        .trimmingCharacters(in: .whitespaces))
    )
    var content = Data()
    while content.count < length {
      content.append(try await readOutputByte())
    }
    return content
  }

  private func readOutputByte() async throws -> UInt8 {
    while pendingOutput.isEmpty {
      guard let chunk = await nextOutputChunk() else {
        throw EndOfOutput()
      }
      pendingOutput = ArraySlice(chunk)
    }
    let byte = pendingOutput.removeFirst()
    capturedOutput.append(byte)
    return byte
  }

  private func nextOutputChunk() async -> Data? {
    for await chunk in outputChunks { return chunk }
    return nil
  }

  private func waitForProcessExit() async {
    guard process.isRunning else { return }
    for await _ in processExit { return }
  }

  private func beforeTimeout<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let timeout = Self.timeout
    return try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await ContinuousClock().sleep(for: timeout)
        throw DeadlineReached()
      }
      defer { group.cancelAll() }
      guard let value = try await group.next() else {
        throw CancellationError()
      }
      return value
    }
  }

  private func terminate() {
    guard process.isRunning else { return }
    process.terminate()
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
  }

  private func timeoutFailure(
    waitingFor operation: String
  ) async -> TransportFailure {
    .timedOut(operation: operation, diagnostics: await diagnostics())
  }

  private func diagnostics() async -> String {
    let standardOutput = String(decoding: capturedOutput, as: UTF8.self)
    let standardError = String(
      decoding: await readStandardError(),
      as: UTF8.self
    )
    let output = standardOutput.isEmpty ? "<empty>" : standardOutput
    let errors = standardError.isEmpty ? "<empty>" : standardError
    return "stdout: \(output)\nstderr: \(errors)"
  }

  private func readStandardError() async -> Data {
    for await chunk in errorChunks { capturedError.append(chunk) }
    return capturedError
  }

  private static func executable() throws -> URL {
    try ExecutableLocator.locate(
      named: "bylaws-lsp",
      overriddenBy: "BYLAWS_LSP_BINARY",
      relativeTo: #filePath
    )
  }
}

private struct DeadlineReached: Error {}
private struct EndOfOutput: Error {}

private struct ServerResponse: Decodable, Sendable {
  let id: Int
  let result: InitializeResult?
}

private struct InitializeResult: Decodable, Sendable {
  struct Capabilities: Decodable, Sendable {
    let hasTextDocumentSync: Bool

    private enum CodingKeys: String, CodingKey {
      case textDocumentSync
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      guard container.contains(.textDocumentSync) else {
        hasTextDocumentSync = false
        return
      }
      hasTextDocumentSync = try !container.decodeNil(
        forKey: .textDocumentSync
      )
    }
  }

  let capabilities: Capabilities
}

private enum TransportFailure: Error, CustomStringConvertible {
  case timedOut(operation: String, diagnostics: String)
  case unexpectedEndOfFile(String)

  var description: String {
    switch self {
    case let .timedOut(operation, diagnostics):
      "Timed out waiting for \(operation) after 5 seconds.\n\(diagnostics)"
    case let .unexpectedEndOfFile(diagnostics):
      "bylaws-lsp closed its output before sending a complete response.\n"
        + diagnostics
    }
  }
}
