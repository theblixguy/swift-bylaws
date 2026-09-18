import SwiftSyntax

/// A syntax node from a Swift source file.
public struct SourceNode: Located, Summarised, Hashable, Sendable {
  let syntax: Syntax
  let context: SourceContext

  /// The node's syntax kind.
  public let kind: Kind

  init(_ syntax: Syntax, context: SourceContext, kind: Kind) {
    self.syntax = syntax
    self.context = context
    self.kind = kind
  }

  /// The node's source text, excluding leading and trailing trivia.
  public var text: String { context.source.trimmedText(of: syntax) }

  /// The call represented by this node, or `nil` for another syntax kind.
  public var call: FunctionCall? {
    if let call = syntax.as(FunctionCallExprSyntax.self) {
      return reader.call(call)
    }
    if let macro = syntax.as(MacroExpansionExprSyntax.self) {
      return reader.call(
        named: macro.macroName.text,
        arguments: macro.arguments,
        at: macro
      )
    }
    if let macro = syntax.as(MacroExpansionDeclSyntax.self) {
      return reader.call(
        named: macro.macroName.text,
        arguments: macro.arguments,
        at: macro
      )
    }
    return nil
  }

  /// The expression represented by this node, or `nil` for another syntax
  /// kind.
  public var expression: SourceExpression? {
    syntax.as(ExprSyntax.self).map {
      SourceExpression($0, source: context.source, origin: context.origin)
    }
  }

  /// The location where the node starts.
  public var location: DeclarationLocation {
    context.location(at: syntax.positionAfterSkippingLeadingTrivia)
  }

  /// The nearest child nodes that `SourceNode` represents, in source order.
  public var children: [Self] {
    modelledChildren(of: syntax)
  }

  /// The represented nodes inside this node, in source order.
  public var descendants: [Self] {
    var result: [Self] = []
    var pending = Array(children.reversed())
    while let node = pending.popLast() {
      result.append(node)
      pending.append(contentsOf: node.children.reversed())
    }
    return result
  }

  /// The nearest containing node that `SourceNode` represents.
  public var parent: Self? {
    var candidate = syntax.parent
    while let syntax = candidate {
      if let kind = Kind(syntax) {
        return Self(syntax, context: context, kind: kind)
      }
      candidate = syntax.parent
    }
    return nil
  }

  /// The represented nodes that contain this node, from its parent to the
  /// source file.
  public var ancestors: [Self] {
    var result: [Self] = []
    var ancestor = parent
    while let node = ancestor {
      result.append(node)
      ancestor = node.parent
    }
    return result
  }

  /// The node's source text.
  public var summary: String { text }

  /// Compares nodes by their syntax kind, source text and location.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.kind == rhs.kind
      && lhs.location == rhs.location
      && lhs.text == rhs.text
  }

  /// Hashes the node's syntax kind and location.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(kind)
    hasher.combine(location)
  }

  private func modelledChildren(of syntax: Syntax) -> [Self] {
    syntax.children(viewMode: .sourceAccurate).flatMap { child in
      if let kind = Kind(child) {
        [Self(child, context: context, kind: kind)]
      } else {
        modelledChildren(of: child)
      }
    }
  }

  private var reader: SyntaxReader {
    SyntaxReader(path: context.origin.filePath, text: context.source)
  }
}

extension SourceNode: CustomStringConvertible {
  /// The node's source text.
  public var description: String { text }
}
