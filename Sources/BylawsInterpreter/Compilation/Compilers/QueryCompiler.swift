import BylawsCore
import BylawsSemantics

enum QueryCompiler {
  typealias Body = @Sendable () async throws -> Violations<Offender>
  typealias BodyFactory = @Sendable (_ excludedSubtrees: [String]) -> Body

  static func compile(
    _ query: QueryExpression,
    over codebase: Codebase
  ) -> Result<BodyFactory, Diagnostic> {
    guard let supportedQuery = SupportedAPI.query(named: query.accessor.name)
    else {
      return .failure(
        .error(
          "'\(query.accessor.name)' is not a query",
          at: query.accessor.location,
          hint: "queries are "
            + SupportedAPI.queries.map(\.name).joined(separator: ", ")
        )
      )
    }
    guard query.accessor.accepts(supportedQuery.argumentContract) else {
      return .failure(
        .error(
          "'\(query.accessor.name)' "
            + supportedQuery.argumentContract.requirement,
          at: query.accessor.location
        )
      )
    }

    return switch supportedQuery.id {
    case .files:
      compile(
        query,
        supportedQuery,
        { try await $0.files },
        over: codebase
      )
    case .classes:
      compile(
        query,
        supportedQuery,
        { try await $0.classes },
        over: codebase
      )
    case .actors:
      compile(
        query,
        supportedQuery,
        { try await $0.actors },
        over: codebase
      )
    case .structs:
      compile(
        query,
        supportedQuery,
        { try await $0.structs },
        over: codebase
      )
    case .enums:
      compile(
        query,
        supportedQuery,
        { try await $0.enums },
        over: codebase
      )
    case .types:
      compile(
        query,
        supportedQuery,
        { try await $0.types },
        over: codebase
      )
    case .protocols:
      compile(
        query,
        supportedQuery,
        { try await $0.protocols },
        over: codebase
      )
    case .extensions:
      compile(
        query,
        supportedQuery,
        { try await $0.extensions },
        over: codebase
      )
    case .functions:
      compile(
        query,
        supportedQuery,
        { try await $0.functions },
        over: codebase
      )
    case .properties:
      compile(
        query,
        supportedQuery,
        { try await $0.properties },
        over: codebase
      )
    case .initializers:
      compile(
        query,
        supportedQuery,
        { try await $0.initializers },
        over: codebase
      )
    case .imports:
      compile(
        query,
        supportedQuery,
        { try await $0.imports },
        over: codebase
      )
    case .typealiases:
      compile(
        query,
        supportedQuery,
        { try await $0.typealiases },
        over: codebase
      )
    case .calls:
      compile(
        query,
        supportedQuery,
        { try await $0.calls },
        over: codebase
      )
    case .expressions:
      compile(
        query,
        supportedQuery,
        { try await $0.expressions },
        over: codebase
      )
    case .compilationBranches:
      compile(
        query,
        supportedQuery,
        { try await $0.compilationBranches },
        over: codebase
      )
    case .assignments:
      compile(
        query,
        supportedQuery,
        { try await $0.assignments },
        over: codebase
      )
    case .variableBindings:
      compile(
        query,
        supportedQuery,
        { try await $0.variableBindings },
        over: codebase
      )
    }
  }

  private static func compile<Element: Named & Located & MatcherSubject>(
    _ query: QueryExpression,
    _ supportedQuery: SupportedAPI.Query,
    _ accessor: @escaping @Sendable (Codebase) async throws
      -> Selection<Element>,
    over codebase: Codebase
  ) -> Result<BodyFactory, Diagnostic> {
    var filters: [
      @Sendable (Selection<Element>) throws -> Selection<Element>
    ] = []
    for filter in query.filters {
      switch compileFilter(filter, as: Element.self) {
      case let .success(apply): filters.append(apply)
      case let .failure(diagnostic): return .failure(diagnostic)
      }
    }
    let check: @Sendable (Selection<Element>) -> Violations<Element>
    switch query.check {
    case let .outsidePaths(patterns):
      check = { Violations(outsidePaths: patterns, in: $0) }
    case let .of(expression), let .matching(expression):
      let matcher: Matcher<Element>
      switch compileMatcher(
        expression,
        for: supportedQuery.declarationFamily,
        as: Element.self
      ) {
      case let .success(compiled): matcher = compiled
      case let .failure(diagnostic): return .failure(diagnostic)
      }
      let requirement = if case .matching = query.check { !matcher }
      else { matcher }
      check = { Violations(of: requirement, in: $0) }
    }
    let compiledFilters = filters
    return .success { subtrees in
      let applied = subtrees.isEmpty
        ? compiledFilters
        : compiledFilters + [{ $0.outside(subtrees) }]
      return {
        var selection = try await accessor(codebase)
        for filter in applied {
          selection = try filter(selection)
        }
        return check(selection).erased()
      }
    }
  }

  private static func compileFilter<Element: Named & Located & Sendable>(
    _ filter: ParsedCall,
    as element: Element.Type
  ) -> Result<
    @Sendable (Selection<Element>) throws -> Selection<Element>,
    Diagnostic
  > {
    guard let supportedFilter = SupportedAPI.filter(named: filter.name) else {
      return .failure(
        .error(
          "'\(filter.name)' is not a filter",
          at: filter.location,
          hint: "filters are "
            + SupportedAPI.filters.map(\.name).joined(separator: ", ")
        )
      )
    }

    guard filter.accepts(supportedFilter.arguments) else {
      return .failure(
        .error(
          "'\(filter.name)' "
            + supportedFilter.arguments.requirement,
          at: filter.location
        )
      )
    }

    let strings = filter.unlabelledStrings
    switch supportedFilter.id {
    case .named: return .success { $0.named(strings) }
    case .suffixed: return .success { $0.suffixed(strings) }
    case .prefixed: return .success { $0.prefixed(strings) }
    case .excluding: return .success { $0.excluding(strings) }
    case .under: return .success { $0.under(strings) }
    case .outside: return .success { $0.outside(strings) }
    case .nameMatching:
      guard let pattern = strings.first, strings.count == 1 else {
        return .failure(
          .error("'nameMatching' takes one pattern", at: filter.location)
        )
      }
      let namePattern: NamePattern
      do {
        namePattern = try NamePattern(pattern)
      } catch {
        return .failure(
          .error(error.description, at: filter.location)
        )
      }
      return .success { $0.nameMatching(namePattern) }
    }
  }

  private static func compileMatcher<Element: MatcherSubject>(
    _ expression: MatcherExpression,
    for declarationFamily: SupportedAPI.DeclarationFamily,
    as element: Element.Type
  ) -> Result<Matcher<Element>, Diagnostic> {
    switch expression {
    case let .leaf(call):
      switch MatcherCompiler.resolve(call, for: declarationFamily) {
      case let .failure(diagnostic):
        return .failure(diagnostic)
      case let .success(supportedMatcher):
        guard let matcher = Element.matcher(supportedMatcher, call) else {
          return .failure(
            .error(
              "'\(call.name)' does not apply to this query's "
                + "declarations",
              at: call.location
            )
          )
        }
        return .success(matcher)
      }
    case let .not(inner):
      return compileMatcher(
        inner,
        for: declarationFamily,
        as: element
      ).map { !$0 }
    case let .and(left, right):
      return compileMatcher(
        left,
        for: declarationFamily,
        as: element
      ).flatMap { compiledLeft in
        compileMatcher(
          right,
          for: declarationFamily,
          as: element
        ).map { compiledLeft && $0 }
      }
    case let .or(left, right):
      return compileMatcher(
        left,
        for: declarationFamily,
        as: element
      ).flatMap { compiledLeft in
        compileMatcher(
          right,
          for: declarationFamily,
          as: element
        ).map { compiledLeft || $0 }
      }
    }
  }
}
