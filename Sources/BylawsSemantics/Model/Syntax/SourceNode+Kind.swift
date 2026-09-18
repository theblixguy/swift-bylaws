import BylawsSyntax

extension SourceNode {
  /// A stable description of a Swift syntax node.
  @nonexhaustive
  public enum Kind: String, CaseIterable, Sendable, Hashable, Codable {
    /// A source file.
    case sourceFile

    /// An actor declaration.
    case actorDeclaration
    /// A class declaration.
    case classDeclaration
    /// A deinitializer declaration.
    case deinitializerDeclaration
    /// An enum declaration.
    case enumDeclaration
    /// An extension declaration.
    case extensionDeclaration
    /// A function declaration.
    case functionDeclaration
    /// An import declaration.
    case importDeclaration
    /// An initializer declaration.
    case initializerDeclaration
    /// A macro declaration.
    case macroDeclaration
    /// A protocol declaration.
    case protocolDeclaration
    /// A struct declaration.
    case structDeclaration
    /// A subscript declaration.
    case subscriptDeclaration
    /// A type alias declaration.
    case typealiasDeclaration
    /// A variable declaration.
    case variableDeclaration

    /// An array expression.
    case arrayExpression
    /// An assignment expression.
    case assignmentExpression
    /// An await expression.
    case awaitExpression
    /// A Boolean literal.
    case booleanLiteral
    /// A closure expression.
    case closureExpression
    /// A conditional compilation block.
    case conditionalCompilation
    /// A dictionary expression.
    case dictionaryExpression
    /// A function call.
    case functionCall
    /// An identifier reference.
    case identifierReference
    /// An if expression.
    case ifExpression
    /// An integer literal.
    case integerLiteral
    /// A macro expansion.
    case macroExpansion
    /// A member access expression.
    case memberAccess
    /// A nil literal.
    case nilLiteral
    /// A string literal.
    case stringLiteral
    /// A switch expression.
    case switchExpression
    /// A try expression.
    case tryExpression
    /// A tuple expression.
    case tupleExpression

    /// A break statement.
    case breakStatement
    /// A continue statement.
    case continueStatement
    /// A defer statement.
    case deferStatement
    /// A discard statement.
    case discardStatement
    /// A do statement.
    case doStatement
    /// An expression statement.
    case expressionStatement
    /// A fallthrough statement.
    case fallthroughStatement
    /// A for statement.
    case forStatement
    /// A guard statement.
    case guardStatement
    /// A repeat statement.
    case repeatStatement
    /// A return statement.
    case returnStatement
    /// A throw statement.
    case throwStatement
    /// A while statement.
    case whileStatement
    /// A yield statement.
    case yieldStatement

    /// An attribute.
    case attribute
    /// A code block.
    case codeBlock
  }
}

extension SourceNode.Kind {
  init?(_ syntax: Syntax) {
    let kind: Self? = switch syntax.kind {
    case .sourceFile: .sourceFile
    case .actorDecl: .actorDeclaration
    case .classDecl: .classDeclaration
    case .deinitializerDecl: .deinitializerDeclaration
    case .enumDecl: .enumDeclaration
    case .extensionDecl: .extensionDeclaration
    case .functionDecl: .functionDeclaration
    case .importDecl: .importDeclaration
    case .initializerDecl: .initializerDeclaration
    case .macroDecl: .macroDeclaration
    case .protocolDecl: .protocolDeclaration
    case .structDecl: .structDeclaration
    case .subscriptDecl: .subscriptDeclaration
    case .typeAliasDecl: .typealiasDeclaration
    case .variableDecl: .variableDeclaration
    case .arrayExpr: .arrayExpression
    case .assignmentExpr: .assignmentExpression
    case .awaitExpr: .awaitExpression
    case .booleanLiteralExpr: .booleanLiteral
    case .closureExpr: .closureExpression
    case .ifConfigDecl: .conditionalCompilation
    case .dictionaryExpr: .dictionaryExpression
    case .functionCallExpr: .functionCall
    case .declReferenceExpr: .identifierReference
    case .ifExpr: .ifExpression
    case .integerLiteralExpr: .integerLiteral
    case .macroExpansionDecl, .macroExpansionExpr: .macroExpansion
    case .memberAccessExpr: .memberAccess
    case .nilLiteralExpr: .nilLiteral
    case .simpleStringLiteralExpr, .stringLiteralExpr: .stringLiteral
    case .switchExpr: .switchExpression
    case .tryExpr: .tryExpression
    case .tupleExpr: .tupleExpression
    case .breakStmt: .breakStatement
    case .continueStmt: .continueStatement
    case .deferStmt: .deferStatement
    case .discardStmt: .discardStatement
    case .doStmt: .doStatement
    case .expressionStmt: .expressionStatement
    case .fallThroughStmt: .fallthroughStatement
    case .forStmt: .forStatement
    case .guardStmt: .guardStatement
    case .repeatStmt: .repeatStatement
    case .returnStmt: .returnStatement
    case .throwStmt: .throwStatement
    case .whileStmt: .whileStatement
    case .yieldStmt: .yieldStatement
    case .attribute: .attribute
    case .codeBlock: .codeBlock
    default: nil
    }
    guard let kind else { return nil }
    self = kind
  }
}
