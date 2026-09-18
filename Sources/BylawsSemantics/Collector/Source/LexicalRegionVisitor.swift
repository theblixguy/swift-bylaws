import BylawsSyntax

class LexicalRegionVisitor: SyntaxVisitor {
  private let visitsTopLevelAccessors: Bool
  private var isInsideTopLevelAccessor = false

  init(visitsTopLevelAccessors: Bool = false) {
    self.visitsTopLevelAccessors = visitsTopLevelAccessors
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: ExtensionDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: InitializerDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: DeinitializerDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: SubscriptDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: MacroExpansionDeclSyntax)
    -> SyntaxVisitorContinueKind
  {
    .skipChildren
  }

  override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
    guard visitsTopLevelAccessors, !isInsideTopLevelAccessor else {
      return .skipChildren
    }
    isInsideTopLevelAccessor = true
    return .visitChildren
  }

  override func visitPost(_ node: AccessorDeclSyntax) {
    isInsideTopLevelAccessor = false
  }
}
