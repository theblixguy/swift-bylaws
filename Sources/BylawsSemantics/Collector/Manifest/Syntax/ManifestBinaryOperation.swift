import BylawsSyntax

// SwiftSyntax writes `a + b` as an InfixOperatorExprSyntax in a parsed
// expression and as a three-element SequenceExprSyntax before the operator
// folds. Manifest collectors read both shapes.
struct ManifestBinaryOperation {
  let leftOperand: ExprSyntax
  let writtenOperator: String
  let rightOperand: ExprSyntax
  let syntax: Syntax

  init?(_ expression: ExprSyntax) {
    if let infix = expression.as(InfixOperatorExprSyntax.self) {
      self.init(infix)
    } else if let sequence = expression.as(SequenceExprSyntax.self) {
      self.init(sequence)
    } else {
      return nil
    }
  }

  init?(_ node: InfixOperatorExprSyntax) {
    guard let writtenOperator = Self.writtenOperator(of: node.operator) else {
      return nil
    }
    leftOperand = node.leftOperand
    self.writtenOperator = writtenOperator
    rightOperand = node.rightOperand
    syntax = Syntax(node)
  }

  init?(_ node: SequenceExprSyntax) {
    let elements = Array(node.elements)
    guard elements.count == 3,
          let writtenOperator = Self.writtenOperator(of: elements[1])
    else { return nil }
    leftOperand = elements[0]
    self.writtenOperator = writtenOperator
    rightOperand = elements[2]
    syntax = Syntax(node)
  }

  func operands(
    forOperator operators: Set<String>
  ) -> (left: ExprSyntax, right: ExprSyntax)? {
    guard operators.contains(writtenOperator) else { return nil }
    return (leftOperand, rightOperand)
  }

  private static func writtenOperator(of expression: ExprSyntax) -> String? {
    if let binary = expression.as(BinaryOperatorExprSyntax.self) {
      return binary.operator.text
    }
    return expression.is(AssignmentExprSyntax.self) ? "=" : nil
  }
}
