import BylawsSyntax

func evaluateCompilationClause(_ clause: IfConfigClauseSyntax) -> Bool? {
  guard let clauseList = Syntax(clause).parent?
    .as(IfConfigClauseListSyntax.self),
    let declaration = Syntax(clauseList).parent?.as(IfConfigDeclSyntax.self)
  else {
    return clause.condition.flatMap(evaluateCompilationCondition)
  }
  for candidate in declaration.clauses {
    let isCurrent = Syntax(candidate) == Syntax(clause)
    if candidate.poundKeyword.tokenKind == .poundElse {
      return isCurrent
    }
    guard let condition = candidate.condition,
          let value = evaluateCompilationCondition(condition)
    else { return nil }
    if value { return isCurrent }
    if isCurrent { return false }
  }
  return false
}

private func evaluateCompilationCondition(_ expression: ExprSyntax) -> Bool? {
  if let sequence = expression.as(SequenceExprSyntax.self) {
    guard let folded = try? OperatorTable.standardOperators.foldSingle(sequence)
    else { return nil }
    return evaluateCompilationCondition(folded)
  }
  if let tuple = expression.as(TupleExprSyntax.self),
     tuple.elements.count == 1,
     let element = tuple.elements.first,
     element.label == nil
  {
    return evaluateCompilationCondition(element.expression)
  }
  if let prefix = expression.as(PrefixOperatorExprSyntax.self),
     prefix.operator.text == "!"
  {
    return evaluateCompilationCondition(prefix.expression).map { !$0 }
  }
  if let operation = ManifestBinaryOperation(expression) {
    let left = evaluateCompilationCondition(operation.leftOperand)
    let right = evaluateCompilationCondition(operation.rightOperand)
    switch operation.writtenOperator {
    case "||":
      if left == true || right == true { return true }
      return left == false && right == false ? false : nil
    case "&&":
      if left == false || right == false { return false }
      return left == true && right == true ? true : nil
    default:
      return nil
    }
  }
  guard let call = expression.as(FunctionCallExprSyntax.self),
        call.manifestAccessPath == ["os"],
        let argument = call.manifestUnlabelledArgument()?
        .as(DeclReferenceExprSyntax.self),
        let operatingSystem = ManifestOperatingSystem(
          rawValue: argument.baseName.text
        )
  else { return nil }
  switch operatingSystem {
  case .macOS:
    #if os(macOS)
      return true
    #else
      return false
    #endif
  case .linux:
    #if os(Linux)
      return true
    #else
      return false
    #endif
  case .windows:
    #if os(Windows)
      return true
    #else
      return false
    #endif
  }
}

private enum ManifestOperatingSystem: String {
  case macOS
  case linux = "Linux"
  case windows = "Windows"
}
