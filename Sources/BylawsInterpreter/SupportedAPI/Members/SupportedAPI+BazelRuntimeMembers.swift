extension SupportedAPI {
  static let bazelRuntimeMembers: [RuntimeMemberAPI] = [
    method(
      .bazelGraph,
      on: [.codebase],
      arguments: .exact([.init(.from, .exact(.string))]),
      result: .fixed(.model(.bazelGraph)),
      canSuspend: true
    ),
    property(
      .targets,
      on: [.model(.bazelGraph)],
      result: .fixed(.array(.model(.bazelTarget)))
    ),
    property(.label, on: [.model(.bazelTarget)], result: .fixed(.string)),
    property(.description, on: [.model(.bazelTarget)], result: .fixed(.string)),
    property(
      .configuration,
      on: [.model(.bazelTarget)],
      result: .fixed(.optional(.model(.bazelConfiguration)))
    ),
    property(
      .ruleClass,
      on: [.model(.bazelTarget)],
      result: .fixed(.optional(.string))
    ),
    property(
      .tags,
      on: [.model(.bazelTarget)],
      result: .fixed(.array(.string))
    ),
    property(
      .location,
      on: [.model(.bazelTarget)],
      result: .fixed(.model(.declarationLocation))
    ),
    property(
      .checksum,
      on: [.model(.bazelConfiguration)],
      result: .fixed(.string)
    ),
    property(
      .isTool,
      on: [.model(.bazelConfiguration)],
      result: .fixed(.boolean)
    ),
    property(
      .buildOptions,
      on: [.model(.bazelConfiguration)],
      result: .fixed(.dictionary(
        key: .string,
        value: .dictionary(key: .string, value: .string)
      ))
    ),
  ] + [.directTargetDependencies, .transitiveTargetDependencies].map { name in
    method(
      name,
      on: [.model(.bazelGraph)],
      arguments: .exact([.init(.of, .exact(.model(.bazelTarget)))]),
      result: .fixed(.array(.model(.bazelTarget)))
    )
  }
}
