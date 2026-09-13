import BylawsCore
import BylawsPaths
import SwiftDiagnostics
import SwiftOperators
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

struct RulesFileParser {
  let syntax: RulesSyntaxContext

  static func parse(source: String, path: String) -> ParsedRulesFile {
    let tree = Parser.parse(source: source)
    let syntax = RulesSyntaxContext(
      path: path,
      converter: SourceLocationConverter(fileName: path, tree: tree)
    )
    let parser = RulesFileParser(syntax: syntax)
    var parsed = ParsedRulesFile(path: path, directory: directory(of: path))

    if tree.hasError {
      parsed.diagnostics = parser.syntaxErrors(in: tree)
      return parsed
    }

    var unfoldable: [Diagnostic] = []
    let folded = OperatorTable.standardOperators.foldAll(tree) { error in
      unfoldable.append(parser.unknownOperator(error))
    }
    guard unfoldable.isEmpty, let file = folded.as(SourceFileSyntax.self)
    else {
      parsed.diagnostics =
        unfoldable.isEmpty
          ? [parser.didNotParse()]
          : unfoldable
      return parsed
    }

    for item in file.statements {
      parser.parse(item, into: &parsed)
    }
    return parsed
  }

  private static func directory(of path: String) -> String {
    LexicalFilePath(path).removingLastComponent().string
  }

  private func parse(
    _ item: CodeBlockItemSyntax,
    into parsed: inout ParsedRulesFile
  ) {
    switch item.item {
    case let .decl(declaration):
      if let imported = declaration.as(ImportDeclSyntax.self) {
        guard imported.importKindSpecifier == nil,
              imported.path.count == 1,
              let moduleName = imported.path.first?.name.text
        else {
          parsed.diagnostics.append(
            syntax.error(
              "portable rules accept one Swift module per import",
              at: imported
            )
          )
          return
        }
        parsed.imports.append(
          ParsedImport(
            moduleName: moduleName,
            location: syntax.location(of: imported)
          )
        )
        return
      }
      if let variable = declaration.as(VariableDeclSyntax.self) {
        let portable = PortableDeclarationParser(syntax: syntax)
        if portable.handles(variable) {
          portable.parse(variable, into: &parsed)
        } else {
          RulesBindingParser(syntax: syntax).parse(variable, into: &parsed)
        }
        return
      }
      if let function = declaration.as(FunctionDeclSyntax.self) {
        PortableDeclarationParser(syntax: syntax).parse(
          function,
          into: &parsed
        )
        return
      }
      parsed.diagnostics.append(unsupported(item))
    case let .expr(expression):
      if let call = expression.as(FunctionCallExprSyntax.self),
         let name = syntax.identifier(of: call.calledExpression),
         let keyword = SupportedAPI.Declaration(rawValue: name)
      {
        RuleDeclarationParser(syntax: syntax).parse(
          call,
          as: keyword,
          into: &parsed
        )
        return
      }
      parsed.diagnostics.append(unsupported(item))
    case .stmt:
      parsed.diagnostics.append(unsupported(item))
    }
  }

  private func syntaxErrors(in tree: SourceFileSyntax) -> [Diagnostic] {
    ParseDiagnosticsGenerator.diagnostics(for: tree).map { error in
      syntax.error(error.message, at: error.node)
    }
  }

  private func unknownOperator(_ error: OperatorError) -> Diagnostic {
    .error(
      "portable rules do not support this operator",
      at: error.syntax.map { syntax.location(of: $0) }
        ?? syntax.startOfFile,
      hint: "a rule's body composes matchers with '&&', '||' and '!'"
    )
  }

  private func didNotParse() -> Diagnostic {
    .error("the file did not parse as Swift", at: syntax.startOfFile)
  }

  private func unsupported(_ item: CodeBlockItemSyntax) -> Diagnostic {
    syntax.error(
      "portable rules do not support this top-level code",
      at: item,
      hint: "a Bylaws.swift file contains Codebase and Layering bindings "
        + "and Rule declarations. Put reusable helpers in an imported rule "
        + "target or other code in a test target"
    )
  }
}

enum PortableImportedModule: String, CaseIterable {
  case foundation = "Foundation"
  case bylaws = "Bylaws"
  case bylawsIndex = "BylawsIndex"
  case bylawsIndexStore = "BylawsIndexStore"
  case swiftSyntax = "SwiftSyntax"
  case testing = "Testing"
}

extension OperatorError {
  fileprivate var syntax: Syntax? {
    switch self {
    case let .missingGroup(_, referencedFrom): referencedFrom
    case let .missingOperator(_, referencedFrom): referencedFrom
    case let .incomparableOperators(leftOperator, _, _, _):
      Syntax(leftOperator)
    case .groupAlreadyExists, .operatorAlreadyExists: nil
    }
  }
}
