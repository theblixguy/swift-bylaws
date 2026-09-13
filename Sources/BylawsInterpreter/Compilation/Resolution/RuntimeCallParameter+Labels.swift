extension SupportedAPI.RuntimeCallParameter {
  var writtenLabel: String? { label.written }
}

func argumentLabelList(_ labels: [String?]) -> String {
  "(" + labels.map { $0.map { "\($0):" } ?? "_" }
    .joined(separator: ", ") + ")"
}

func argumentCountDescription(_ count: Int) -> String {
  "\(count) \(count == 1 ? "argument" : "arguments")"
}
