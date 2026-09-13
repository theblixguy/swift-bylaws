struct PriceFormatter {
  func format(_ pence: Int) -> String {
    "£\(pence / 100).\(pence % 100)"
  }
}

enum Legacy {
  class Helper {
    func migrate() {}
  }
}
