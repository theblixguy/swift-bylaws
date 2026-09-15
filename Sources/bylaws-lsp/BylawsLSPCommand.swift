import BylawsLSP
import BylawsRunner
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import SKLogging

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@main
struct BylawsLSPCommand {
  static func main() async {
    if CommandLine.arguments.dropFirst() == ["--version"] {
      FileHandle.standardOutput.write(
        Data("\(BylawsVersion.current)\n".utf8)
      )
      return
    }

    LoggingScope.configureDefaultLoggingSubsystem("bylaws-lsp")

    let connection = JSONRPCConnection(
      name: "bylaws-lsp",
      protocol: .lspProtocol,
      receiveFD: .standardInput,
      sendFD: .standardOutput
    )
    let server = BylawsLanguageServer(
      client: connection,
      onExit: { cleanExit in
        if cleanExit {
          connection.close()
        } else {
          exit(EXIT_FAILURE)
        }
      }
    )
    await withCheckedContinuation { continuation in
      connection.start(receiveHandler: server) {
        continuation.resume()
      }
    }
  }
}
