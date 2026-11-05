import BylawsCore
import BylawsSemantics
import Foundation

indirect enum RuntimeValue: Sendable {
  case array([RuntimeValue])
  case arraySlice(ArraySlice<RuntimeValue>)
  case boolean(Bool)
  case boundMethod(receiver: RuntimeValue, name: SupportedAPI.Method)
  case closure(RuntimeClosure)
  case codebase(Codebase)
  case dependencyGroup(DependencyGroup)
  case dictionary([RuntimeDictionaryKey: RuntimeValue])
  case double(Double)
  case findings(Rule.Findings)
  case ruleResults(RuleResults)
  case function(RuntimeFunction)
  case genericType(name: String, arguments: [SupportedAPI.RuntimeType])
  case model(RuntimeModelValue)
  case integer(Int)
  case integerRange(Range<Int>)
  case integerClosedRange(ClosedRange<Int>)
  case integerRangeFrom(PartialRangeFrom<Int>)
  case integerRangeThrough(PartialRangeThrough<Int>)
  case integerRangeUpTo(PartialRangeUpTo<Int>)
  case keyPath([SupportedAPI.Member], DeclarationLocation)
  case layering(Layering)
  case layer(Layer)
  case manifestList(RuntimeManifestList)
  case matcher(RuntimeMatcher)
  case member(SupportedAPI.MemberLiteral)
  case optional(RuntimeValue?)
  case projectIndex(RuntimeProjectIndex)
  case rule(RuntimeRule)
  case set([RuntimeValue])
  case symbolRoles(Set<RuntimeSymbolRole>)
  case selection(RuntimeSelection)
  case string(String)
  case regex(RuntimeRegex)
  case sourceSlice(SourceSlice)
  case sourceList(RuntimeSourceList)
  case sourceListPosition(SourceListPosition)
  case sourceEdit(SourceFix.Edit)
  case sourceFix(SourceFix)
  case sourceCorrection(SourceCorrection)
  case layoutCorrection(SourceCorrection)
  case sourceReplacement(SourceReplacement)
  case sourceScope(Scope)
  case sourceLayout(SourceLayout)
  case sourceLayoutCondition(SourceLayoutCondition)
  case layoutPlan([RuntimeLayoutOperation])
  case layoutGroup(RuntimeLayoutGroup)
  case sourceSpacing(SourceSpacing)
  case fixContext(RuntimeFixContext)
  case url(URL)
  case violations(RuntimeViolations)
  case void
}

extension RuntimeValue {
  var sequenceValues: AnySequence<RuntimeValue>? {
    switch self {
    case let .array(values), let .set(values): AnySequence(values)
    case let .arraySlice(values): AnySequence(values)
    case let .sourceList(list): AnySequence(list.elements)
    case let .selection(selection):
      AnySequence(selection.elements.lazy.map(RuntimeValue.model))
    case let .integerRange(range):
      AnySequence(range.lazy.map(RuntimeValue.integer))
    case let .integerClosedRange(range):
      AnySequence(range.lazy.map(RuntimeValue.integer))
    default: nil
    }
  }

  var sequenceElements: [RuntimeValue]? {
    switch self {
    case let .array(values), let .set(values): values
    case let .arraySlice(values): Array(values)
    case let .sourceList(list): list.elements
    case let .selection(selection): selection.elements.map(RuntimeValue.model)
    default: nil
    }
  }

  var ruleResult: (any RuleResult)? {
    switch self {
    case let .violations(value): value.erased
    case let .findings(value): value
    case let .ruleResults(value): value
    case let .model(.check(value)): value.ruleResult
    default: nil
    }
  }

  static func member(named name: String) -> Self? {
    SupportedAPI.MemberLiteral(rawValue: name).map(member)
  }

  static func member(naming value: some RawRepresentable<String>) -> Self? {
    member(named: value.rawValue)
  }

  func hasRuntimeType(_ type: SupportedAPI.RuntimeType) -> Bool {
    switch (type, self) {
    case let (.dictionary(key, value), .dictionary(values)):
      values.allSatisfy {
        $0.key.value.hasRuntimeType(key) && $0.value.hasRuntimeType(value)
      }
    case let (.optional(wrapped), .optional(value)):
      value?.hasRuntimeType(wrapped) ?? true
    case let (.array(element), .array(values)):
      values.allSatisfy { $0.hasRuntimeType(element) }
    case let (.arraySlice(element), .arraySlice(values)):
      values.allSatisfy { $0.hasRuntimeType(element) }
    case let (.sourceList(element), .sourceList(list)):
      list.elements.allSatisfy { $0.hasRuntimeType(element) }
    case let (.manifestList(element), .manifestList(value)):
      value.possibleValues.allSatisfy { $0.hasRuntimeType(element) }
    case let (.set(element), .set(values)):
      values.allSatisfy { $0.hasRuntimeType(element) }
    case let (.selection(family), .selection(selection)):
      selection.family == family
    case let (.model(type), .model(value)):
      value.modelType == type
    case let (.staticMember(owners), .member(literal)):
      !owners.isDisjoint(with: literal.owners)
    case let (.staticMember(owners), .sourceListPosition):
      owners.contains(.sourceListPosition)
    case let (.matcher(subject), .matcher(matcher)):
      subject == nil || matcher.subjectType == nil
        || matcher.subjectType == subject
    case let (.violations(subject), .violations(violations)):
      subject == nil
        || violations.offenders.allSatisfy { $0.modelType == subject }
    case (.sourceSlice, .sourceSlice), (.sourceEdit, .sourceEdit): true
    case (.sourceFix, .sourceFix): true
    case (.sourceCorrection, .sourceCorrection), (
      .layoutCorrection,
      .layoutCorrection
    ): true
    case (.sourceReplacement, .sourceReplacement),
         (.sourceScope, .sourceScope): true
    case (.sourceLayout, .sourceLayout): true
    case (.sourceLayoutCondition, .sourceLayoutCondition): true
    case (.integerClosedRange, .integerClosedRange),
         (.integerRangeFrom, .integerRangeFrom),
         (.integerRangeThrough, .integerRangeThrough),
         (.integerRangeUpTo, .integerRangeUpTo): true
    case (.layoutContent, .sourceLayout), (.layoutContent, .layoutGroup), (
      .layoutContent,
      .layoutPlan
    ): true
    case let (.sourceLayout, .member(literal)): literal.owners
      .contains(.sourceLayout)
    case (.sourceLayout, .layoutPlan), (.layoutGroup, .layoutGroup): true
    case (.conditionalLayoutOperation, .layoutPlan),
         (.layoutOperation(.newline), .layoutPlan),
         (.layoutOperation(.blankLine), .layoutPlan): true
    case (.layoutOperation, .sourceLayout): true
    case (.sourceSpacing, .sourceSpacing): true
    case let (.fixContext(subject), .fixContext(context)):
      subject == nil || context.offender.modelType == subject
    case (.findings, .findings):
      true
    case (.ruleResults, .ruleResults): true
    case (.boolean, .boolean), (.string, .string), (.integer, .integer),
         (.double, .double), (.regex, .regex), (.codebase, .codebase),
         (.integerRange, .integerRange), (.layering, .layering),
         (.layer, .layer), (.dependencyGroup, .dependencyGroup),
         (.rule, .rule), (.void, .void), (.projectIndex, .projectIndex),
         (.symbolRoles, .symbolRoles), (.url, .url):
      true
    default:
      false
    }
  }

  var optionalChained: Self {
    if case .optional = self { return self }
    return .optional(self)
  }

  func coerced(to type: SupportedAPI.RuntimeType) -> Self? {
    if hasRuntimeType(type) { return self }
    switch (type, self) {
    case let (.double, .integer(value)):
      return .double(Double(value))
    case let (.array(element), .array(values)):
      let coerced = values.compactMap { $0.coerced(to: element) }
      return coerced.count == values.count ? .array(coerced) : nil
    case let (.arraySlice(element), .arraySlice(values)):
      var result = values
      for index in values.indices {
        guard let value = values[index].coerced(to: element) else { return nil }
        result[index] = value
      }
      return .arraySlice(result)
    case let (.arraySlice(element), .array(values)):
      let coerced = values.compactMap { $0.coerced(to: element) }
      return coerced.count == values.count ? .arraySlice(coerced[...]) : nil
    case let (.set(element), .set(values)):
      let coerced = values.compactMap { $0.coerced(to: element) }
      return coerced.count == values.count ? .set(coerced) : nil
    case let (.optional(wrapped), value):
      if case .optional = value { return nil }
      return value.coerced(to: wrapped).map { .optional($0) }
    default:
      return nil
    }
  }
}
