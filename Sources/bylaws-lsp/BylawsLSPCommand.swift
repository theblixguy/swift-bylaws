import BylawsLSP
import BylawsRunner
import Dispatch
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@main
struct BylawsLSPCommand {
  static func main() {
    if CommandLine.arguments.dropFirst() == ["--version"] {
      FileHandle.standardOutput.write(
        Data("\(BylawsVersion.current)\n".utf8)
      )
      return
    }

    let finished = DispatchSemaphore(value: 0)
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
    connection.start(receiveHandler: server) {
      finished.signal()
    }
    finished.wait()
  }
}
