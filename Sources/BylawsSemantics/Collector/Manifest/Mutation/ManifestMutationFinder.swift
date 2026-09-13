import SwiftSyntax

struct ManifestMutation {
  let field: ManifestPackageField
  let syntax: Syntax
  let value: ExprSyntax?
  let isList: Bool
  let replacesValues: Bool
  let invalidatesExistingValues: Bool
  let conditionHolds: Bool?
}

private struct ManifestAssignment {
  enum Operation {
    case replace
    case append

    init?(writtenOperator: String) {
      switch writtenOperator {
      case "=": self = .replace
      case "+=": self = .append
      default: return nil
      }
    }
  }

  let leftOperand: ExprSyntax
  let operation: Operation
  let rightOperand: ExprSyntax
  let syntax: Syntax

  init?(_ operation: ManifestBinaryOperation?) {
    guard let operation,
          let kind = Operation(writtenOperator: operation.writtenOperator)
    else { return nil }
    leftOperand = operation.leftOperand
    self.operation = kind
    rightOperand = operation.rightOperand
    syntax = operation.syntax
  }
}

final class ManifestMutationFinder: SyntaxVisitor {
  private let packageInitializationEndOffset: Int

  private(set) var mutations: [ManifestMutation] = []
  private var targetBindings: Set<String> = []

  init(after packageCall: FunctionCallExprSyntax) {
    packageInitializationEndOffset = packageCall
      .endPositionBeforeTrailingTrivia.utf8Offset
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: FunctionCallExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    guard isInPackageProgram(node) else { return .skipChildren }
    let mutationCount = mutations.count
    recordFieldCall(node)
    if hasPackageArgument(node) {
      recordEscape(node)
    } else {
      recordUnmodelledCall(node, ifNoMutationsSince: mutationCount)
    }
    return .visitChildren
  }

  override func visit(_ node: InfixOperatorExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    guard isInPackageProgram(node) else { return .skipChildren }
    guard let assignment = ManifestAssignment(ManifestBinaryOperation(node))
    else {
      return .visitChildren
    }
    record(assignment)
    return .visitChildren
  }

  override func visit(_ node: SequenceExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    guard isInPackageProgram(node) else { return .skipChildren }
    guard let assignment = ManifestAssignment(ManifestBinaryOperation(node))
    else {
      return .visitChildren
    }
    record(assignment)
    return .visitChildren
  }

  private func record(_ assignment: ManifestAssignment) {
    let mutationCount = mutations.count
    if let field = packageField(in: assignment.leftOperand) {
      mutations.append(
        ManifestMutation(
          field: field,
          syntax: assignment.syntax,
          value: assignment.rightOperand,
          isList: field.isCollection,
          replacesValues: assignment.operation == .replace,
          invalidatesExistingValues: false,
          conditionHolds: conditionHolds(containing: assignment.syntax)
        )
      )
    }
    recordUnmodelledAssignment(
      leftOperand: assignment.leftOperand,
      rightOperand: assignment.rightOperand,
      syntax: assignment.syntax,
      ifNoMutationsSince: mutationCount
    )
  }

  override func visit(_ node: VariableDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    guard isInPackageProgram(node) else { return .skipChildren }
    for binding in node.bindings where bindingDeclaresTarget(binding) {
      guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?
        .identifier.text
      else { continue }
      targetBindings.insert(name)
    }
    guard node.bindings.contains(where: {
      $0.initializer.map { containsPackageReference($0.value) } == true
    })
    else { return .visitChildren }
    recordEscape(node)
    return .visitChildren
  }

  private func recordEscape(_ node: some SyntaxProtocol) {
    for field in ManifestPackageField.allCases {
      mutations.append(
        ManifestMutation(
          field: field,
          syntax: Syntax(node),
          value: nil,
          isList: false,
          replacesValues: false,
          invalidatesExistingValues: true,
          conditionHolds: conditionHolds(containing: node)
        )
      )
    }
  }

  private func recordInvalidation(
    of field: ManifestPackageField,
    at node: some SyntaxProtocol
  ) {
    mutations.append(
      ManifestMutation(
        field: field,
        syntax: Syntax(node),
        value: nil,
        isList: false,
        replacesValues: false,
        invalidatesExistingValues: true,
        conditionHolds: conditionHolds(containing: node)
      )
    )
  }

  private func recordFieldCall(_ call: FunctionCallExprSyntax) {
    guard let path = call.manifestAccessPath,
          path.count == 3,
          path[0] == "package",
          let field = ManifestPackageField(rawValue: path[1])
    else { return }
    if field.isCollection {
      guard let method = ManifestCollectionMutation(rawValue: path[2])
      else { return }
      let supported = method == .append
      let contentsOf = call.manifestArgument(labelled: "contentsOf")
      mutations.append(
        ManifestMutation(
          field: field,
          syntax: Syntax(call),
          value: supported
            ? contentsOf ?? call.manifestUnlabelledArgument()
            : nil,
          isList: contentsOf != nil,
          replacesValues: false,
          invalidatesExistingValues: !supported,
          conditionHolds: conditionHolds(containing: call)
        )
      )
    } else {
      recordInvalidation(of: field, at: call)
    }
  }

  private func recordUnmodelledCall(
    _ call: FunctionCallExprSyntax,
    ifNoMutationsSince mutationCount: Int
  ) {
    guard mutations.count == mutationCount, isStandaloneCall(call)
    else { return }
    if isTargetMutation(call) {
      recordInvalidation(of: .targets, at: call)
    } else if isPotentialPackageCapturingCall(call),
              occursAfterPackageInitialization(call)
    {
      recordEscape(call)
    }
  }

  private func hasPackageArgument(_ call: FunctionCallExprSyntax) -> Bool {
    call.arguments.contains { containsPackageReference($0.expression) }
  }

  private func recordUnmodelledAssignment(
    leftOperand: ExprSyntax,
    rightOperand: ExprSyntax,
    syntax: some SyntaxProtocol,
    ifNoMutationsSince mutationCount: Int
  ) {
    guard mutations.count == mutationCount else { return }
    if containsTargetField(leftOperand) {
      recordInvalidation(of: .targets, at: syntax)
    } else if containsPackageReference(rightOperand) {
      recordEscape(syntax)
    }
  }

  private func isTargetMutation(_ call: FunctionCallExprSyntax) -> Bool {
    guard let method = call.calledExpression.as(MemberAccessExprSyntax.self),
          ManifestCollectionMutation(
            rawValue: method.declName.baseName.text
          ) != nil
    else { return false }
    return containsTargetField(call.calledExpression)
  }

  private func containsTargetField(_ expression: some SyntaxProtocol) -> Bool {
    let names = manifestMemberNames(in: expression)
    let references = manifestReferenceNames(in: expression)
    guard ManifestTargetField.allCases.contains(where: {
      names.contains($0.rawValue)
    }) else { return false }
    if names.contains(ManifestPackageField.targets.rawValue),
       containsPackageReference(expression)
    {
      return true
    }
    return !references.isDisjoint(with: targetBindings)
  }

  private func packageField(in expression: ExprSyntax)
    -> ManifestPackageField?
  {
    guard let path = expression.manifestAccessPath,
          path.count == 2,
          path[0] == "package"
    else { return nil }
    return ManifestPackageField(rawValue: path[1])
  }

  private func bindingDeclaresTarget(_ binding: PatternBindingSyntax) -> Bool {
    if let type = binding.typeAnnotation?.type,
       manifestTypeName(type) == "Target"
    {
      return true
    }
    guard let call = binding.initializer?.value
      .as(FunctionCallExprSyntax.self)
    else { return false }
    return call.manifestCallName?.isTargetFactory == true
  }

  private func manifestTypeName(_ type: TypeSyntax) -> String? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
      return identifier.name.text
    }
    if let member = type.as(MemberTypeSyntax.self) {
      return member.name.text
    }
    return nil
  }

  private func occursAfterPackageInitialization(
    _ node: some SyntaxProtocol
  ) -> Bool {
    node.positionAfterSkippingLeadingTrivia.utf8Offset
      > packageInitializationEndOffset
  }

  private func isPotentialPackageCapturingCall(
    _ call: FunctionCallExprSyntax
  ) -> Bool {
    call.calledExpression.is(DeclReferenceExprSyntax.self)
  }

  private func isStandaloneCall(_ node: FunctionCallExprSyntax) -> Bool {
    var current = Syntax(node).parent
    while let syntax = current {
      if syntax.is(CodeBlockItemSyntax.self) { return true }
      if syntax.is(FunctionCallExprSyntax.self)
        || syntax.is(VariableDeclSyntax.self)
        || syntax.is(InfixOperatorExprSyntax.self)
        || syntax.is(SequenceExprSyntax.self)
        || syntax.is(ArrayExprSyntax.self)
        || syntax.is(DictionaryExprSyntax.self)
        || syntax.is(TupleExprSyntax.self)
        || syntax.is(IfConfigClauseSyntax.self)
        || syntax.is(IfExprSyntax.self)
        || syntax.is(SwitchExprSyntax.self)
      {
        return false
      }
      current = syntax.parent
    }
    return false
  }

  private func isInPackageProgram(_ node: some SyntaxProtocol) -> Bool {
    var current = Syntax(node).parent
    while let syntax = current {
      if syntax.is(FunctionDeclSyntax.self)
        || syntax.is(InitializerDeclSyntax.self)
        || syntax.is(DeinitializerDeclSyntax.self)
        || syntax.is(AccessorDeclSyntax.self)
        || syntax.is(ClosureExprSyntax.self)
        || syntax.is(MemberBlockSyntax.self)
      {
        return false
      }
      current = syntax.parent
    }
    return true
  }

  private func conditionHolds(
    containing node: some SyntaxProtocol
  ) -> Bool? {
    var current = Syntax(node).parent
    var result = true
    while let syntax = current {
      if syntax.is(IfExprSyntax.self)
        || syntax.is(SwitchExprSyntax.self)
        || syntax.is(ForStmtSyntax.self)
        || syntax.is(WhileStmtSyntax.self)
        || syntax.is(RepeatStmtSyntax.self)
        || syntax.is(DoStmtSyntax.self)
      {
        return nil
      }
      if let clause = syntax.as(IfConfigClauseSyntax.self) {
        guard let value = evaluateCompilationClause(clause)
        else { return nil }
        result = result && value
      }
      current = syntax.parent
    }
    return result
  }

  private func containsPackageReference(
    _ expression: some SyntaxProtocol
  ) -> Bool {
    let finder = PackageReferenceFinder(viewMode: .sourceAccurate)
    finder.walk(Syntax(expression))
    return finder.found
  }
}

private final class PackageReferenceFinder: SyntaxVisitor {
  private(set) var found = false

  override func visit(_ node: DeclReferenceExprSyntax)
    -> SyntaxVisitorContinueKind
  {
    guard node.baseName.text == "package" else { return .skipChildren }
    if let member = Syntax(node).parent?.as(MemberAccessExprSyntax.self),
       member.base.map({
         manifestReferenceNames(in: $0).contains("package")
       }) != true
    {
      return .skipChildren
    }
    found = true
    return .skipChildren
  }
}
