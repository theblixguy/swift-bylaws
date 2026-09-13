extension SupportedAPI {
  struct ManifestMemberTable {
    typealias RuntimeMemberAPI = SupportedAPI.RuntimeMemberAPI

    let manifestList: Set<RuntimeReceiver> = [.manifestList]
    let manifest = RuntimeReceiver.model(.packageManifest)
    let target = RuntimeReceiver.model(.manifestTarget)
    let string = RuntimeType.string
    let integer = RuntimeType.integer
    let boolean = RuntimeType.boolean

    func model(_ type: ModelType) -> Set<RuntimeReceiver> { [.model(type)] }
    func list(_ element: RuntimeType) -> RuntimeType { .manifestList(element) }
    func optional(_ wrapped: RuntimeType) -> RuntimeType { .optional(wrapped) }
    func array(_ element: RuntimeType) -> RuntimeType { .array(element) }
    func set(_ element: RuntimeType) -> RuntimeType { .set(element) }
    func member(_ owner: MemberLiteral.Owner) -> RuntimeType {
      .staticMember([owner])
    }

    func relationshipMethod(_ name: Member) -> RuntimeMemberAPI {
      method(
        name,
        on: [.model(.packageManifest)],
        arguments: .alternatives([
          [.init(.of, .exact(.model(.manifestTarget)))],
          [
            .init(.of, .exact(.model(.manifestTarget))),
            .init(.includingConditionalDependencies, .exact(.boolean)),
          ],
        ]),
        result: .fixed(.manifestList(.model(.manifestTarget)))
      )
    }

    func testTargetMethod() -> RuntimeMemberAPI {
      method(
        .testTargets,
        on: [.model(.packageManifest)],
        arguments: .alternatives([
          [.init(.dependingDirectlyOn, .exact(.model(.manifestTarget)))],
          [
            .init(.dependingDirectlyOn, .exact(.model(.manifestTarget))),
            .init(.includingConditionalDependencies, .exact(.boolean)),
          ],
          [.init(.dependingOn, .exact(.model(.manifestTarget)))],
          [
            .init(.dependingOn, .exact(.model(.manifestTarget))),
            .init(.includingConditionalDependencies, .exact(.boolean)),
          ],
        ]),
        result: .fixed(.manifestList(.model(.manifestTarget)))
      )
    }
  }
}
