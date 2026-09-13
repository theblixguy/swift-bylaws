public import BylawsSemantics

extension Codebase {
  /// The source files in the codebase.
  ///
  /// - Throws: ``CodebaseError/unreadable(failures:)`` when the root
  ///   directory or one of its source files cannot be read, and
  ///   ``CodebaseError/didNotParse(paths:)`` when a file's syntax carries
  ///   an error.
  public var files: Selection<SourceFile> {
    get async throws(CodebaseError) {
      try await selection(of: .files, labelled: "files") { $0 }
    }
  }

  /// The classes declared in the codebase, including nested classes.
  ///
  /// - Throws: The errors ``files`` throws.
  public var classes: Selection<Class> {
    get async throws(CodebaseError) {
      try await selection(of: .classes, labelled: "classes") {
        $0.flatMap(\.classes)
      }
    }
  }

  /// The actors declared in the codebase, including nested actors.
  ///
  /// - Throws: The errors ``files`` throws.
  public var actors: Selection<Actor> {
    get async throws(CodebaseError) {
      try await selection(of: .actors, labelled: "actors") {
        $0.flatMap(\.actors)
      }
    }
  }

  /// The structs declared in the codebase, including nested structs.
  ///
  /// - Throws: The errors ``files`` throws.
  public var structs: Selection<Struct> {
    get async throws(CodebaseError) {
      try await selection(of: .structs, labelled: "structs") {
        $0.flatMap(\.structs)
      }
    }
  }

  /// The enums declared in the codebase, including nested enums.
  ///
  /// - Throws: The errors ``files`` throws.
  public var enums: Selection<Enum> {
    get async throws(CodebaseError) {
      try await selection(of: .enums, labelled: "enums") {
        $0.flatMap(\.enums)
      }
    }
  }

  /// The nominal types declared in the codebase, including nested types.
  ///
  /// Query protocol declarations through ``protocols``.
  ///
  /// - Throws: The errors ``files`` throws.
  public var types: Selection<NominalType> {
    get async throws(CodebaseError) {
      try await selection(of: .types, labelled: "types") {
        $0.flatMap(\.types)
      }
    }
  }

  /// The protocols declared in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var protocols: Selection<ProtocolDeclaration> {
    get async throws(CodebaseError) {
      try await selection(
        of: .protocols,
        labelled: "protocols",
        create: { $0.flatMap(\.protocols) }
      )
    }
  }

  /// The extensions declared in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var extensions: Selection<Extension> {
    get async throws(CodebaseError) {
      try await selection(
        of: .extensions,
        labelled: "extensions",
        create: { $0.flatMap(\.extensions) }
      )
    }
  }

  /// The functions declared in the codebase, including member functions.
  ///
  /// - Throws: The errors ``files`` throws.
  public var functions: Selection<Function> {
    get async throws(CodebaseError) {
      try await selection(
        of: .functions,
        labelled: "functions",
        create: { $0.flatMap(\.functions) }
      )
    }
  }

  /// The properties declared in the codebase, including member properties.
  ///
  /// - Throws: The errors ``files`` throws.
  public var properties: Selection<Property> {
    get async throws(CodebaseError) {
      try await selection(
        of: .properties,
        labelled: "properties",
        create: { $0.flatMap(\.properties) }
      )
    }
  }

  /// The initialisers declared in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var initializers: Selection<Initializer> {
    get async throws(CodebaseError) {
      try await selection(
        of: .initializers,
        labelled: "initializers",
        create: { $0.flatMap(\.initializers) }
      )
    }
  }

  /// The imports declared in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var imports: Selection<Import> {
    get async throws(CodebaseError) {
      try await selection(of: .imports, labelled: "imports") {
        $0.flatMap(\.imports)
      }
    }
  }

  /// The typealiases declared in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var typealiases: Selection<Typealias> {
    get async throws(CodebaseError) {
      try await selection(
        of: .typealiases,
        labelled: "typealiases",
        create: { $0.flatMap(\.typealiases) }
      )
    }
  }

  /// The call expressions and declaration macros in the codebase.
  ///
  /// - Throws: The errors ``files`` throws.
  public var calls: Selection<FunctionCall> {
    get async throws(CodebaseError) {
      try await selection(of: .calls, labelled: "calls") {
        $0.flatMap(\.calls)
      }
    }
  }

  private func selection<Element>(
    of category: ParsedCodebase.Projection,
    labelled label: String,
    create: @escaping @Sendable ([SourceFile]) -> [Element]
  ) async throws(CodebaseError) -> Selection<Element> {
    let parsedCodebase = try await CodebaseCache.shared
      .parsedCodebase(for: self)
    let storage = await parsedCodebase.projection(
      for: category,
      create: create
    )
    let description = "\(label) in \(parsedCodebase.rootName)"
    QueryInspection.record(
      query: description,
      selected: storage.elements.compactMap(SelectionInspection.Element.init)
    )
    return Selection(
      storage: storage,
      queryDescription: description,
      rootPath: parsedCodebase.rootPath
    )
  }
}
