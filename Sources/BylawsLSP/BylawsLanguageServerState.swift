import BylawsCore
import BylawsPaths
import BylawsRunner
import Foundation
import LanguageServerProtocol

actor BylawsLanguageServerState {
  private let clock: any Clock<Duration>
  private let client: any Connection
  private let runner: RuleRunning
  private var diagnosticMode = DiagnosticMode.push
  private var documentTexts: [DocumentURI: String] = [:]
  private var generation: UInt = 0
  private var initializationOptions: InitializationOptions?
  private var openDocuments: Set<DocumentURI> = []
  private var pendingRefresh: (task: Task<Void, Never>, isDelayed: Bool)?
  private var publishedDocuments: Set<DocumentURI> = []
  private var rootPath: LexicalFilePath?
  private var snapshot: DiagnosticSnapshot?
  private var supportsDiagnosticRefresh = false
  private var wasShutDown = false

  init(
    clock: any Clock<Duration>,
    client: any Connection,
    runner: RuleRunning = .standard
  ) {
    self.clock = clock
    self.client = client
    self.runner = runner
  }

  func initialize(_ request: InitializeRequest) -> InitializeResult {
    let path = request.workspaceFolders?.first?.uri.fileURL?.path
      ?? request.rootURI?.fileURL?.path
      ?? request.rootPath
    let resolvedRoot = path.map {
      LexicalFilePath($0, relativeTo: .currentDirectory)
    } ?? .currentDirectory
    rootPath = resolvedRoot
    initializationOptions = InitializationOptions(
      request.initializationOptions,
      root: resolvedRoot
    )
    diagnosticMode = request.capabilities.textDocument?.diagnostic == nil
      ? .push
      : .pull
    supportsDiagnosticRefresh =
      request.capabilities.workspace?.diagnostics?.refreshSupport == true

    return InitializeResult(
      capabilities: ServerCapabilities(
        positionEncoding: .utf16,
        textDocumentSync: .options(
          TextDocumentSyncOptions(
            openClose: true,
            change: .full,
            willSave: false,
            willSaveWaitUntil: false,
            save: .value(.init(includeText: false))
          )
        ),
        diagnosticProvider: diagnosticMode == .pull
          ? DiagnosticOptions(
            identifier: "bylaws",
            interFileDependencies: true,
            workspaceDiagnostics: false
          )
          : nil
      )
    )
  }

  func shutdown() {
    cancelPendingRefresh()
    wasShutDown = true
  }

  var canExitSuccessfully: Bool { wasShutDown }

  var isServing: Bool { rootPath != nil && !wasShutDown }

  func initialized() async {
    guard diagnosticMode == .push else { return }
    await refreshDiagnostics()
  }

  func didOpen(_ notification: DidOpenTextDocumentNotification) {
    let uri = notification.textDocument.uri
    openDocuments.insert(uri)
    documentTexts[uri] = notification.textDocument.text
    scheduleRefresh(after: .zero)
  }

  func didChange(_ notification: DidChangeTextDocumentNotification) {
    let uri = notification.textDocument.uri
    documentTexts[uri] = notification.contentChanges
      .last { $0.range == nil }?.text
    scheduleRefresh()
  }

  func didSave(_ notification: DidSaveTextDocumentNotification) async {
    cancelPendingRefresh()
    let saveGeneration = generation
    documentTexts[notification.textDocument.uri] = nil
    if let rootPath {
      await runner.discardCaches(rootPath.string)
    }
    guard saveGeneration == generation, !wasShutDown else { return }
    await refreshDiagnostics()
  }

  func didClose(_ notification: DidCloseTextDocumentNotification) {
    let uri = notification.textDocument.uri
    openDocuments.remove(uri)
    guard documentTexts.removeValue(forKey: uri) != nil else { return }
    scheduleRefresh()
  }

  func waitForPendingRefresh() async {
    while let pendingRefresh {
      let requestGeneration = generation
      await pendingRefresh.task.value
      if requestGeneration == generation {
        self.pendingRefresh = nil
      }
    }
  }

  func diagnostics(
    for request: DocumentDiagnosticsRequest
  ) async -> DocumentDiagnosticReport {
    let uri = request.textDocument.uri
    if pendingRefresh?.isDelayed == true {
      await refreshDiagnostics()
    } else if pendingRefresh != nil {
      await waitForPendingRefresh()
    } else if snapshot == nil {
      await refreshDiagnostics()
    }
    guard let snapshot else {
      return .full(RelatedFullDocumentDiagnosticReport(items: []))
    }
    if request.previousResultId == snapshot.resultID {
      return .unchanged(
        RelatedUnchangedDocumentDiagnosticReport(
          resultId: snapshot.resultID
        )
      )
    }
    return .full(
      RelatedFullDocumentDiagnosticReport(
        resultId: snapshot.resultID,
        items: snapshot.diagnosticsByURI[uri, default: []]
      )
    )
  }

  private func cancelPendingRefresh() {
    pendingRefresh?.task.cancel()
    pendingRefresh = nil
    generation &+= 1
  }

  private func scheduleRefresh(after delay: Duration? = nil) {
    cancelPendingRefresh()
    let requestGeneration = generation
    let delay = delay ?? initializationOptions?.refreshDelay ?? .zero
    let clock = clock
    let task = Task { @concurrent in
      if delay > .zero {
        try? await clock.sleep(for: delay)
      }
      guard !Task.isCancelled else { return }
      await self.updateDiagnostics(for: requestGeneration)
    }
    pendingRefresh = (task, delay > .zero)
  }

  private func refreshDiagnostics() async {
    scheduleRefresh(after: .zero)
    await waitForPendingRefresh()
  }

  private func updateDiagnostics(for requestGeneration: UInt) async {
    guard let rootPath, requestGeneration == generation,
          !wasShutDown else { return }
    pendingRefresh?.isDelayed = false
    let options = initializationOptions ?? InitializationOptions(
      nil,
      root: rootPath
    )
    let overlay = unsavedOverlay()
    let configuration = RuleRunConfiguration(
      root: rootPath,
      ruleFilePaths: options.ruleFilePaths,
      only: options.only,
      skip: options.skip,
      strict: options.strict,
      baseline: options.baseline,
      parseCachePolicy: .environment(cachesTemporaryRoots: true),
      overlay: overlay,
      swiftPackageModules: options.swiftPackageModules
    )
    let result: RuleRunResult
    do {
      result = try await runner.run(configuration)
    } catch {
      return
    }
    guard requestGeneration == generation, !wasShutDown,
          !Task.isCancelled else { return }
    if snapshot != nil, onlyTheEditorTextDidNotParse(result, in: overlay) {
      return
    }
    if result.outcome == .notConfigured {
      snapshot = DiagnosticSnapshot(
        diagnosticsByURI: [:],
        resultID: String(generation)
      )
    } else {
      snapshot = DiagnosticSnapshot(
        document: result.document,
        overlay: overlay,
        generation: generation
      )
    }
    notifyClientAfterRefresh()
  }

  private func onlyTheEditorTextDidNotParse(
    _ result: RuleRunResult,
    in overlay: SourceOverlay
  ) -> Bool {
    guard !result.pathsThatDidNotParse.isEmpty else { return false }
    return result.pathsThatDidNotParse.allSatisfy {
      overlay.text(forFileAt: $0) != nil
    }
  }

  private func unsavedOverlay() -> SourceOverlay {
    SourceOverlay(
      Dictionary(
        documentTexts.compactMap { uri, text in
          uri.fileURL.map { ($0.path, text) }
        },
        uniquingKeysWith: { first, _ in first }
      )
    )
  }

  private func notifyClientAfterRefresh() {
    switch diagnosticMode {
    case .pull:
      if supportsDiagnosticRefresh {
        _ = client.send(DiagnosticsRefreshRequest()) { _ in }
      }
    case .push:
      publishAllDiagnostics()
    }
  }

  private func publishAllDiagnostics() {
    guard let snapshot else { return }
    let documents = publishedDocuments
      .union(snapshot.diagnosticsByURI.keys)
      .union(openDocuments)
    for uri in documents {
      publishDiagnostics(for: uri)
    }
    publishedDocuments = Set(snapshot.diagnosticsByURI.keys)
  }

  private func publishDiagnostics(for uri: DocumentURI) {
    client.send(
      PublishDiagnosticsNotification(
        uri: uri,
        diagnostics: snapshot?.diagnosticsByURI[uri, default: []] ?? []
      )
    )
  }
}
