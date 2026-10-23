enum FormattingMock {
  static let statements = """
  func submit() async throws {
    let request = try makeRequest()
    await log(request)
    try await persist(request)
  }

  """

  static let spacedStatements = """
  func submit() async throws {
    let request = try makeRequest()

    await log(request)

    try await persist(request)
  }

  """

  static let properties = #"""
  struct ReaderPanel {
    let onClose: () -> Void
    @State private var query = ""
    @Environment(Settings.self) private var settings
    private let store: Store
    @Environment(\.locale) private var locale
    @State private var isExpanded = false
    @Environment(\.isEnabled) private var isEnabled
  }
  """# + "\n"

  static let groupedProperties = #"""
  struct ReaderPanel {
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    @Environment(Settings.self) private var settings

    @State private var query = ""
    @State private var isExpanded = false

    private let store: Store
    let onClose: () -> Void
  }
  """# + "\n"

  static let call = #"""
  func finished() {
    logger.write(.info, "Download finished", category: "Transfer", metadata: [.init(key: "bytes", value: transfer.byteCount)])
  }
  """# + "\n"

  static let multilineCall = #"""
  func finished() {
    logger.write(
      .info, "Download finished",
      category: "Transfer",
      metadata: [
        .init(key: "bytes", value: transfer.byteCount)
      ]
    )
  }
  """# + "\n"

  static let combined = #"""
  #if canImport(SwiftUI)
  import SwiftUI

  struct ReaderPanel {
    let onClose: () -> Void
    @State private var isExpanded = false
    @Environment(\.locale) private var locale
    private let resourceName: String?
  }
  #endif

  func publish() async throws {
    let message = "Ready"
    print(message, terminator: "!")
    try writeArchive(message)
    print("done")
  }

  func writeArchive(_ message: String) throws {}
  """# + "\n"

  static let formattedCombined = #"""
  #if canImport(SwiftUI)
  import SwiftUI

  struct ReaderPanel {
    @Environment(\.locale) private var locale

    @State private var isExpanded = false

    private let resourceName: String?
    let onClose: () -> Void
  }
  #endif

  func publish() async throws {
    let message = "Ready"

    print(
      message,
      terminator: "!"
    )

    try writeArchive(message)

    print("done")
  }

  func writeArchive(_ message: String) throws {}
  """# + "\n"
}
