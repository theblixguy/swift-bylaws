extension SupportedAPI {
  package enum Member: String, CaseIterable, Hashable, Sendable {
    case stringValue, integerValue, floatingPointValue, booleanValue
    case isNilLiteral, referenceName, referenceLocation, base, arrayElements
    case dictionaryElements
    case interpolations, key
    case expressions
    case assignments
    case variableBindings
    case operatorName
    case initialValue
    case isMutable
    case enclosingDeclarations
    case deletingLastPathComponent
    case lastPathComponent
    case pathExtension
    case mapValues
    case all, any, none
    case `where`
    case actors
    case affectedPath
    case aliasedTypeName
    case allInheritedTypes
    case allSatisfy
    case argumentLabels
    case arguments
    case attribute
    case attributes
    case awaitCount
    case baseName
    case bazelGraph
    case isTool
    case buildOptions
    case ruleClass
    case tags
    case binarySource
    case bodyLineCount
    case branch
    case buildMetadataIdentifiers
    case buildSettings
    case calledExpression
    case calls
    case cases
    case checkDependencyStability
    case checkDependencies
    case checkDependencyCycles
    case dependencyGroups
    case checkedCount
    case checks
    case checkedEdgeCount
    case checkedImportCount
    case checkLayering
    case checkFolderLayout
    case checkPackageDependencies
    case checksum
    case cLanguageStandard
    case classes
    case column
    case compactMap
    case components
    case condition
    case conditionalValues
    case configuration
    case conformers
    case conforms
    case constraintName
    case contains
    case count
    case cxxLanguageStandard
    case cyclomaticComplexity
    case defaultIsolation
    case defaultLocalization
    case defaultTraitNames
    case definitions
    case dependencies
    case dependencyNames
    case description
    case directConformers
    case directlyConforms
    case directlyInherits
    case directTargetDependencies
    case documentation
    case elementType
    case emptyLayers
    case emptyTargets
    case enabledTraitNames
    case enclosingTypeName
    case enums
    case excludedPaths
    case excluding
    case expression
    case extendedTypeName
    case extensionInheritedTypes
    case extensions
    case field
    case file
    case fileName
    case filePath
    case files
    case filter
    case findings
    case first
    case flatMap
    case functions
    case genericArguments
    case genericParameters
    case hasArgumentLabel
    case hasAttribute
    case hasPrefix
    case hasSuffix
    case importDeclaration
    case importedBy
    case importedInstability
    case importedTarget
    case importGraph
    case imports
    case indexedFindings
    case inheritedTypes
    case inherits
    case initializers
    case instability
    case intent
    case isActor
    case isArray
    case isAsync
    case isClass
    case isComment
    case isComplete
    case isConstant
    case isConvenience
    case isDictionary
    case isDocumented
    case isDynamic
    case isEmpty
    case isEnum
    case isExactVersion
    case isExistential
    case isFailable
    case isFinal
    case isFunction
    case isIndirect
    case isLazy
    case isMutating
    case isNonisolated
    case isNonisolatedUnsafe
    case isOpaque
    case isOptional
    case isOverride
    case isPlugin
    case isSet
    case isStatic
    case isStruct
    case isSubset
    case isTest
    case isThrowing
    case isTuple
    case isWeak
    case keyType
    case keyword
    case kind
    case kindType = "Kind"
    case knownValues
    case label
    case layer
    case leadingTrivia
    case line
    case lineCount
    case linkage
    case localization
    case location
    case lowerBound
    case major
    case majorVersion
    case map
    case memberBlock
    case memberName
    case members
    case message
    case minimumVersion
    case minor
    case missingImports
    case matchedFolders
    case missingFolders
    case unexpectedFolders
    case module
    case moduleName
    case name
    case named
    case nameMatching
    case networkScope
    case occurrences
    case offenders
    case outside
    case ownership
    case packageAccess
    case packageManifest
    case packageName
    case packages
    case parameters
    case patch
    case path
    case paths
    case permissions
    case pkgConfig
    case platforms
    case pluginCapability
    case plugins
    case ports
    case possibleValues
    case prefixed
    case prereleaseIdentifiers
    case products
    case projectIndex
    case properties
    case protocols
    case providers
    case publicHeadersPath
    case qualifiedName
    case queryDescription
    case rawValue
    case reason
    case references
    case requiredFunctions
    case requiredImport
    case requiredProperties
    case requirement
    case requirementDescription
    case resources
    case returnType
    case returnTypeName
    case revision
    case roles
    case rule
    case selfType = "self"
    case simpleExtendedTypeName
    case sourceDirectory
    case sourceKind
    case sourceLocation
    case sourceRange
    case sources
    case sourceText
    case structs
    case suffixed
    case swiftLanguageModes
    case symbol
    case target
    case targetNames
    case targets
    case testTargets
    case text
    case tokens
    case tool
    case toolsVersion
    case trailingTrivia
    case traitNames
    case traits
    case transitiveTargetDependencies
    case type
    case typealiases
    case typeName
    case types
    case undeclared
    case under
    case unresolvedManifestValues
    case unresolvedValues
    case unstable
    case unused
    case upperBound
    case usesUnsafeFlags
    case usr
    case utf8Offset
    case value
    case valueKind
    case values
    case valueType
    case verb
    case violations
    case visibility
    case warningLevel
    case warnings
    case withSyntax

    var method: Method? {
      Method(rawValue: rawValue)
    }
  }

  package enum Method: String, CaseIterable, Sendable {
    case bazelGraph
    case deletingLastPathComponent
    case mapValues
    case all, any, none
    case `where`
    case allSatisfy
    case attribute
    case calls
    case checkDependencyStability
    case checkDependencies
    case checkDependencyCycles
    case dependencyGroups
    case checkLayering
    case checkFolderLayout
    case checkPackageDependencies
    case compactMap
    case conformers
    case conforms
    case contains
    case definitions
    case dependencies
    case directConformers
    case directlyConforms
    case directlyInherits
    case directTargetDependencies
    case excluding
    case filter
    case findings
    case flatMap
    case hasArgumentLabel
    case hasAttribute
    case hasPrefix
    case hasSuffix
    case importGraph
    case imports
    case indexedFindings
    case inherits
    case isSubset
    case map
    case named
    case nameMatching
    case occurrences
    case outside
    case prefixed
    case products
    case projectIndex
    case references
    case suffixed
    case targets
    case testTargets
    case tokens
    case transitiveTargetDependencies
    case under
    case violations
    case withSyntax
  }

  package enum Constructor: String, CaseIterable, Sendable {
    case url = "URL"
    case dictionary = "Dictionary"
    case dependencyGroup = "DependencyGroup"
    case ruleResults = "RuleResults"
    case layer = "Layer"
    case layering = "Layering"
    case array = "Array"
    case matcher = "Matcher"
    case rule = "Rule"
    case set = "Set"
    case trivia = "Trivia"
    case violations = "Violations"
  }

  package enum ModelType: String, CaseIterable, Sendable {
    case sourceExpression = "SourceExpression"
    case sourceAssignment = "SourceAssignment"
    case variableBinding = "VariableBinding"
    case enclosingDeclaration = "EnclosingDeclaration"
    case expressionArgument = "SourceExpression.Argument"
    case dictionaryElement = "SourceExpression.DictionaryElement"
    case callArgument = "FunctionCall.Argument"
    case bazelGraph = "BazelGraph"
    case bazelTarget = "BazelGraph.Target"
    case bazelConfiguration = "BazelGraph.Configuration"
    case actor = "Actor"
    case attribute = "Attribute"
    case classDeclaration = "Class"
    case declarationLocation = "DeclarationLocation"
    case dependencyStabilityCheck = "DependencyStabilityCheck"
    case enumCase = "EnumCase"
    case enumDeclaration = "Enum"
    case extensionDeclaration = "Extension"
    case function = "Function"
    case functionCall = "FunctionCall"
    case genericParameter = "GenericParameter"
    case importDeclaration = "Import"
    case importGraph = "ImportGraph"
    case importGraphTarget = "ImportGraph.Target"
    case indexReference = "IndexReference"
    case indexSymbol = "IndexSymbol"
    case initializer = "Initializer"
    case layeringCheck = "LayeringCheck"
    case folderLayoutCheck = "FolderLayoutCheck"
    case manifestBinarySource = "PackageManifest.Target.BinarySource"
    case manifestCondition = "PackageManifest.Condition"
    case manifestDependency = "PackageManifest.Dependency"
    case manifestDependencyRequirement = "PackageManifest.Dependency.Requirement"
    case manifestDependencyTraitSelection = "PackageManifest.Dependency.TraitSelection"
    case manifestNetworkPorts = "PackageManifest.Target.NetworkPorts"
    case manifestNetworkScope = "PackageManifest.Target.NetworkScope"
    case manifestPlatform = "PackageManifest.Platform"
    case manifestPlatformVersion = "PackageManifest.PlatformVersion"
    case manifestPluginCapability = "PackageManifest.Target.PluginCapability"
    case manifestPluginIntent = "PackageManifest.Target.PluginIntent"
    case manifestPluginPermission = "PackageManifest.Target.PluginPermission"
    case manifestProduct = "PackageManifest.Product"
    case manifestTarget = "PackageManifest.Target"
    case manifestTargetDependency = "PackageManifest.Target.Dependency"
    case manifestTargetPluginUsage = "PackageManifest.Target.PluginUsage"
    case manifestTargetResource = "PackageManifest.Target.Resource"
    case manifestTargetSetting = "PackageManifest.Target.Setting"
    case manifestTargetSourceSelection = "PackageManifest.Target.SourceSelection"
    case manifestTargetSystemPackageProvider = "PackageManifest.Target.SystemPackageProvider"
    case manifestToolsVersion = "PackageManifest.ToolsVersion"
    case manifestTrait = "PackageManifest.Trait"
    case manifestUnresolvedValue = "PackageManifest.UnresolvedValue"
    case manifestVersion = "PackageManifest.Version"
    case missingImport = "LayeringCheck.MissingImport"
    case nominalType = "NominalType"
    case offender = "Offender"
    case packageDependencyCheck = "PackageDependencyCheck"
    case packageManifest = "PackageManifest"
    case parameter = "Parameter"
    case property = "Property"
    case protocolDeclaration = "ProtocolDeclaration"
    case ruleWarning = "Rule.Warning"
    case sourceFile = "SourceFile"
    case structDeclaration = "Struct"
    case syntaxClass = "ClassDeclSyntax"
    case syntaxMemberBlock = "MemberBlockSyntax"
    case syntaxSourceFile = "SourceFileSyntax"
    case syntaxToken = "TokenSyntax"
    case syntaxTriviaPiece = "TriviaPiece"
    case typealiasDeclaration = "Typealias"
    case typeReference = "TypeReference"
    case undeclaredDependency = "PackageDependencyCheck.UndeclaredDependency"
    case unstableDependency = "DependencyStabilityCheck.UnstableDependency"
    case unusedDependency = "PackageDependencyCheck.UnusedDependency"

    package init?(declarationFamily: DeclarationFamily) {
      switch declarationFamily {
      case .file: self = .sourceFile
      case .class: self = .classDeclaration
      case .actor: self = .actor
      case .struct: self = .structDeclaration
      case .enum: self = .enumDeclaration
      case .nominalType: self = .nominalType
      case .protocol: self = .protocolDeclaration
      case .extension: self = .extensionDeclaration
      case .function: self = .function
      case .property: self = .property
      case .initializer: self = .initializer
      case .import: self = .importDeclaration
      case .typealias: self = .typealiasDeclaration
      case .functionCall: self = .functionCall
      case .sourceExpression: self = .sourceExpression
      case .sourceAssignment: self = .sourceAssignment
      case .variableBinding: self = .variableBinding
      }
    }
  }
}
