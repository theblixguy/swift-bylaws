import BylawsRunner

extension ReportDocument.Level {
  var compilerName: String {
    switch self {
    case .error: "error"
    case .warning: "warning"
    case .notice: "note"
    }
  }

  var reportName: String {
    switch self {
    case .error: "error"
    case .warning: "warning"
    case .notice: "notice"
    }
  }
}
