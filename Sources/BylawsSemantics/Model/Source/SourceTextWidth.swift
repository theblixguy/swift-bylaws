package enum SourceTextWidth {
  package static func column(
    after text: some StringProtocol, startingAt start: Int = 0,
    tabWidth: Int = 8
  ) -> Int {
    let tabWidth = max(tabWidth, 1)
    return text.reduce(start) { column, character in
      if character == "\n" || character == "\r" || character ==
        "\r\n" { return 0 }
      let advance = character == "\t" ? tabWidth - column % tabWidth : 1
      let next = column.addingReportingOverflow(advance)
      return next.overflow ? Int.max : next.partialValue
    }
  }

  package static func exceeds(
    _ maximumWidth: Int,
    in text: some StringProtocol,
    startingAt start: Int = 0,
    tabWidth: Int = 8
  ) -> Bool {
    guard start <= maximumWidth else { return true }
    let tabWidth = max(tabWidth, 1)
    var column = start
    for character in text {
      let advance = character == "\t" ? tabWidth - column % tabWidth : 1
      if advance > maximumWidth - column { return true }
      column += advance
    }
    return false
  }
}
