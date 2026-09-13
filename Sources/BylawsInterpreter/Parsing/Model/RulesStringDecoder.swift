import SwiftParser
import SwiftSyntax

enum RulesStringDecoder {
  static func string(_ expression: ExprSyntax) -> String? {
    expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
  }

  static func array(_ expression: ExprSyntax) -> [String]? {
    guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
    var values: [String] = []
    for element in array.elements {
      guard let value = string(element.expression) else { return nil }
      values.append(value)
    }
    return values
  }
}
