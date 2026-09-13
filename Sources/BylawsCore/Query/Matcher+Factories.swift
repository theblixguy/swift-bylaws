public import BylawsSemantics

extension Matcher where Subject: Named {
  /// Matches declarations named exactly one of `names`.
  public static func named(_ names: String...) -> Matcher {
    named(names)
  }

  /// Matches declarations named exactly one of `names`.
  public static func named(_ names: [String]) -> Matcher {
    Matcher("be named \(names.quotedList)") { names.contains($0.name) }
  }

  /// Matches declarations whose name ends with one of `suffixes`.
  public static func suffixed(_ suffixes: String...) -> Matcher {
    suffixed(suffixes)
  }

  /// Matches declarations whose name ends with one of `suffixes`.
  public static func suffixed(_ suffixes: [String]) -> Matcher {
    Matcher("have a name suffixed \(suffixes.quotedList)") { subject in
      suffixes.contains { subject.name.hasSuffix($0) }
    }
  }

  /// Matches declarations whose name begins with one of `prefixes`.
  public static func prefixed(_ prefixes: String...) -> Matcher {
    prefixed(prefixes)
  }

  /// Matches declarations whose name begins with one of `prefixes`.
  public static func prefixed(_ prefixes: [String]) -> Matcher {
    Matcher("have a name prefixed \(prefixes.quotedList)") { subject in
      prefixes.contains { subject.name.hasPrefix($0) }
    }
  }

  /// Matches declarations whose name matches the regular expression
  /// `pattern`.
  ///
  /// - Throws: ``CodebaseError/invalidRegularExpression(pattern:)`` when
  ///   `pattern` is invalid.
  public static func nameMatching(
    _ pattern: String
  ) throws(CodebaseError) -> Matcher {
    nameMatching(try NamePattern(pattern))
  }

  package static func nameMatching(_ namePattern: NamePattern) -> Matcher {
    Matcher("have a name matching /\(namePattern.pattern)/") {
      namePattern.matches($0.name)
    }
  }
}

extension Matcher where Subject: InheritanceProviding {
  /// Matches declarations that inherit from one of `typeNames`, directly
  /// or through intermediate types declared in the codebase.
  public static func inherits(from typeNames: String...) -> Matcher {
    inherits(from: typeNames)
  }

  /// Matches declarations that inherit from one of `typeNames`, directly
  /// or through intermediate types declared in the codebase.
  public static func inherits(from typeNames: [String]) -> Matcher {
    Matcher("inherit from \(typeNames.quotedList)") { subject in
      typeNames.contains { subject.inherits(from: $0) }
    }
  }

  /// Matches declarations whose own inheritance clause includes one of
  /// `typeNames`.
  public static func directlyInherits(from typeNames: String...) -> Matcher {
    directlyInherits(from: typeNames)
  }

  /// Matches declarations whose own inheritance clause includes one of
  /// `typeNames`.
  public static func directlyInherits(from typeNames: [String]) -> Matcher {
    Matcher("directly inherit from \(typeNames.quotedList)") { subject in
      typeNames.contains { subject.directlyInherits(from: $0) }
    }
  }

  /// Matches declarations that conform to one of `typeNames`.
  ///
  /// The conformance may be direct, added by an extension or inherited
  /// through an intermediate type declared in the codebase.
  public static func conforms(to typeNames: String...) -> Matcher {
    conforms(to: typeNames)
  }

  /// Matches declarations that conform to one of `typeNames`.
  ///
  /// The conformance may be direct, added by an extension or inherited
  /// through an intermediate type declared in the codebase.
  public static func conforms(to typeNames: [String]) -> Matcher {
    Matcher("conform to \(typeNames.quotedList)") { subject in
      typeNames.contains { subject.conforms(to: $0) }
    }
  }

  /// Matches declarations that name one of `typeNames` in their own
  /// inheritance clause or gain it through an extension anywhere in the
  /// codebase.
  public static func directlyConforms(to typeNames: String...) -> Matcher {
    directlyConforms(to: typeNames)
  }

  /// Matches declarations that name one of `typeNames` in their own
  /// inheritance clause or gain it through an extension anywhere in the
  /// codebase.
  public static func directlyConforms(to typeNames: [String]) -> Matcher {
    Matcher("directly conform to \(typeNames.quotedList)") { subject in
      typeNames.contains { subject.directlyConforms(to: $0) }
    }
  }

  /// Matches declarations whose inheritance contains `entry` exactly as written.
  ///
  /// The entry may come from the declaration or an extension. Attributes are
  /// significant. `"@unchecked Sendable"` and `"Sendable"` are different
  /// entries.
  public static func declaresInheritance(_ entry: String) -> Matcher {
    Matcher("declare '\(entry)' in the inheritance clause") { subject in
      subject.inheritedTypes.contains(entry)
        || subject.extensionInheritedTypes.contains(entry)
    }
  }
}

extension Matcher where Subject: Visible {
  /// Matches declarations with `public` or `open` visibility.
  public static var isPublic: Matcher {
    Matcher("be public") { $0.isPublic }
  }

  /// Matches declarations at least as visible as `level`.
  public static func hasVisibility(atLeast level: Visibility) -> Matcher {
    Matcher("be at least as visible as '\(level)'") { $0.visibility >= level }
  }
}

extension Matcher where Subject: Attributed {
  /// Matches declarations bearing one of the attributes in `names`, with
  /// or without `@`.
  public static func hasAttribute(_ names: String...) -> Matcher {
    hasAttribute(names)
  }

  /// Matches declarations bearing one of the attributes in `names`, with
  /// or without `@`.
  public static func hasAttribute(_ names: [String]) -> Matcher {
    let displayed = names
      .map { "@" + ($0.hasPrefix("@") ? String($0.dropFirst()) : $0) }
      .quotedList
    return Matcher("have the attribute \(displayed)") { subject in
      names.contains { subject.hasAttribute($0) }
    }
  }
}

extension Matcher<Class> {
  /// Matches classes marked `final`.
  public static var isFinal: Matcher {
    Matcher("be final") { $0.isFinal }
  }
}

extension Matcher<NominalType> {
  /// Matches types written with the `class` keyword.
  public static var isClass: Matcher {
    Matcher("be a class") { $0.isClass }
  }

  /// Matches types written with the `struct` keyword.
  public static var isStruct: Matcher {
    Matcher("be a struct") { $0.isStruct }
  }

  /// Matches types written with the `enum` keyword.
  public static var isEnum: Matcher {
    Matcher("be an enum") { $0.isEnum }
  }

  /// Matches types written with the `actor` keyword.
  public static var isActor: Matcher {
    Matcher("be an actor") { $0.isActor }
  }
}

extension Matcher<SourceFile> {
  /// Matches files that import one of `modules`.
  public static func imports(_ modules: String...) -> Matcher {
    imports(modules)
  }

  /// Matches files that import one of `modules`.
  public static func imports(_ modules: [String]) -> Matcher {
    Matcher("import \(modules.quotedList)", witnessedBy: { file in
      file.imports.first { statement in
        modules.contains { statement.references($0) }
      }?.location
    })
  }

  /// Matches files with a call that references one of `identifiers`.
  public static func calls(_ identifiers: String...) -> Matcher {
    calls(identifiers)
  }

  /// Matches files with a call that references one of `identifiers`.
  public static func calls(_ identifiers: [String]) -> Matcher {
    Matcher("call \(identifiers.quotedList)", witnessedBy: { file in
      file.firstCall { call in
        identifiers.contains { call.references($0) }
      }?.location
    })
  }
}

extension Matcher where Subject: Documented {
  /// Matches declarations with a documentation comment.
  public static var hasDocumentation: Matcher {
    Matcher("have a documentation comment") { $0.isDocumented }
  }
}

extension Matcher<Function> {
  /// Matches functions with a call that references one of `identifiers`.
  public static func calls(_ identifiers: String...) -> Matcher {
    calls(identifiers)
  }

  /// Matches functions with a call that references one of `identifiers`.
  public static func calls(_ identifiers: [String]) -> Matcher {
    Matcher("call \(identifiers.quotedList)", witnessedBy: { function in
      function.calls.first { call in
        identifiers.contains { call.references($0) }
      }?.location
    })
  }

  /// Matches functions marked `override`.
  public static var isOverride: Matcher {
    Matcher("be an override") { $0.isOverride }
  }

  /// Matches functions whose return type is `typeName`, as written.
  public static func returns(_ typeName: String) -> Matcher {
    Matcher("return '\(typeName)'") { $0.returnTypeName == typeName }
  }

  /// Matches functions with a parameter whose type is `typeName`, as written.
  public static func hasParameter(typed typeName: String) -> Matcher {
    Matcher("have a parameter of type '\(typeName)'") {
      $0.parameters.contains { $0.typeName == typeName }
    }
  }

  /// Matches functions with a parameter labelled `label`.
  public static func hasParameter(labelled label: String) -> Matcher {
    Matcher("have a parameter labelled '\(label)'") {
      $0.parameters.contains { $0.label == label }
    }
  }

  /// Matches functions marked `mutating`.
  public static var isMutating: Matcher {
    Matcher("be mutating") { $0.isMutating }
  }

  /// Matches functions marked `dynamic`.
  public static var isDynamic: Matcher {
    Matcher("be dynamic") { $0.isDynamic }
  }

  /// Matches functions declared `async`.
  public static var isAsync: Matcher {
    Matcher("be async") { $0.isAsync }
  }

  /// Matches functions declared `throws` or `rethrows`.
  public static var isThrowing: Matcher {
    Matcher("be throwing") { $0.isThrowing }
  }

  /// Matches functions marked `nonisolated`.
  public static var isNonisolated: Matcher {
    Matcher("be nonisolated") { $0.isNonisolated }
  }

  /// Matches functions with a parameter whose written type contains one of
  /// `typeNames` at any depth.
  ///
  /// For example, `[Order]` contains `"Order"`.
  public static func hasParameter(referencing typeNames: String...) -> Matcher {
    hasParameter(referencing: typeNames)
  }

  /// Matches functions with a parameter whose written type contains one of
  /// `typeNames` at any depth.
  ///
  /// For example, `[Order]` contains `"Order"`.
  public static func hasParameter(referencing typeNames: [String]) -> Matcher {
    Matcher("have a parameter referencing \(typeNames.quotedList)") { function in
      function.parameters.contains { parameter in
        typeNames.contains { parameter.type.references($0) }
      }
    }
  }

  /// Matches functions whose written return type is optional.
  public static var returnsOptional: Matcher {
    Matcher("return an optional") { $0.returnType?.isOptional == true }
  }
}

extension Matcher<Property> {
  /// Matches properties declared `weak`.
  public static var isWeak: Matcher {
    Matcher("be weak") { $0.isWeak }
  }

  /// Matches properties whose initialiser value or accessors hold a call
  /// that references one of `identifiers`.
  public static func calls(_ identifiers: String...) -> Matcher {
    calls(identifiers)
  }

  /// Matches properties whose initialiser value or accessors hold a call
  /// that references one of `identifiers`.
  public static func calls(_ identifiers: [String]) -> Matcher {
    Matcher("call \(identifiers.quotedList)", witnessedBy: { property in
      property.calls.first { call in
        identifiers.contains { call.references($0) }
      }?.location
    })
  }

  /// Matches properties marked `lazy`.
  public static var isLazy: Matcher {
    Matcher("be lazy") { $0.isLazy }
  }

  /// Matches properties marked `dynamic`.
  public static var isDynamic: Matcher {
    Matcher("be dynamic") { $0.isDynamic }
  }

  /// Matches properties marked `nonisolated`.
  public static var isNonisolated: Matcher {
    Matcher("be nonisolated") { $0.isNonisolated }
  }

  /// Matches properties marked `nonisolated(unsafe)`.
  public static var isNonisolatedUnsafe: Matcher {
    Matcher("be nonisolated(unsafe)") { $0.isNonisolatedUnsafe }
  }

  /// Matches properties with an optional written type annotation.
  public static var hasOptionalType: Matcher {
    Matcher("have an optional type") { $0.type?.isOptional == true }
  }

  /// Matches properties whose written type is one of `typeNames`.
  ///
  /// The comparison ignores optionality: `Order` and `Order?` both match
  /// `"Order"`. A collection type such as `[Order]` matches `"Array"`.
  public static func hasType(_ typeNames: String...) -> Matcher {
    hasType(typeNames)
  }

  /// Matches properties whose written type is one of `typeNames`.
  ///
  /// The comparison ignores optionality: `Order` and `Order?` both match
  /// `"Order"`. A collection type such as `[Order]` matches `"Array"`.
  public static func hasType(_ typeNames: [String]) -> Matcher {
    Matcher("have the type \(typeNames.quotedList)") { property in
      guard let name = property.type?.name else { return false }
      return typeNames.contains(name)
    }
  }

  /// Matches properties whose written type contains one of `typeNames` at any
  /// depth.
  ///
  /// For example, `[String: Order]` contains `"Order"`.
  public static func referencesType(_ typeNames: String...) -> Matcher {
    referencesType(typeNames)
  }

  /// Matches properties whose written type contains one of `typeNames` at any
  /// depth.
  ///
  /// For example, `[String: Order]` contains `"Order"`.
  public static func referencesType(_ typeNames: [String]) -> Matcher {
    Matcher("reference the type \(typeNames.quotedList)") { property in
      guard let type = property.type else { return false }
      return typeNames.contains { type.references($0) }
    }
  }
}

extension Matcher<Initializer> {
  /// Matches initialisers marked `convenience`.
  public static var isConvenience: Matcher {
    Matcher("be a convenience initialiser") { $0.isConvenience }
  }
}

extension Matcher<Enum> {
  /// Matches enums marked `indirect`.
  public static var isIndirect: Matcher {
    Matcher("be indirect") { $0.isIndirect }
  }
}

extension Matcher<FunctionCall> {
  /// Matches calls whose called expression matches one of `identifiers`.
  ///
  /// Identifiers follow ``/BylawsSemantics/FunctionCall/references(_:)`` and
  /// may include a dotted path and argument labels.
  public static func references(_ identifiers: String...) -> Matcher {
    references(identifiers)
  }

  /// Matches calls whose called expression matches one of `identifiers`.
  ///
  /// Identifiers follow ``/BylawsSemantics/FunctionCall/references(_:)`` and
  /// may include a dotted path and argument labels.
  public static func references(_ identifiers: [String]) -> Matcher {
    Matcher("reference \(identifiers.quotedList)") { call in
      identifiers.contains { call.references($0) }
    }
  }

  /// Matches calls with an argument labelled `label`.
  public static func hasArgumentLabel(_ label: String) -> Matcher {
    Matcher("have an argument labelled '\(label)'") {
      $0.hasArgumentLabel(label)
    }
  }
}
