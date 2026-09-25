# ``BylawsIndex``

Find compiler-resolved definitions, references and conformances from a
`Codebase`.

## Overview

After building your project, you can use `BylawsIndex` to find which code refers
to a symbol or which types conform to a protocol across modules. You can also
check dependencies between folders within one module, where import rules
cannot distinguish the layers.

Run the rules on macOS or Linux with a Swift toolchain installed. For an iOS
project, use a macOS test target or command-line tool to check the app's build.

A SwiftPM debug build writes index data by default, while a release build needs
`--enable-index-store`. Bylaws searches for the store as described in
``/BylawsIndexStore/IndexStoreLocation``. If your build uses another location,
set `BYLAWS_INDEX_STORE` to that path.

You can add the `BylawsIndex` product to your test target to query the same
`Codebase` as your other rules. This example checks that the types which conform
to `Repository` belong to the `Data` module:

```swift
import Bylaws
import BylawsIndex
import BylawsIndexStore
import Testing

@Test("Repository conformers belong to the data layer")
func repositoriesStayInData() async throws {
    let conformers = try await Codebase.app.conformers(
        of: "Repository",
        modules: ["Domain", "Data"]
    )
    let outsideDataLayer = conformers.filter { $0.module != "Data" }
    #expect(outsideDataLayer.isEmpty)
}
```

Index queries use the `Codebase` file selection by default, and you can pass
`modules:` when a rule needs every indexed file in specific modules.

A store with several builds of the same source file can produce an error about
which build to use. Choose a store for one configuration or select its units
with `unitOutputFiles:` in
``/BylawsIndex/BylawsCore/Codebase/projectIndex(modules:unitOutputFiles:)``.
Pass the ``/BylawsIndexStore/IndexUnit/outputFile`` values unchanged when
selecting units.

To read index records without using a `Codebase` or parsing the source, add
the `BylawsIndexStore` product and import its module instead.

## Topics

### Codebase queries

- <doc:/BylawsIndex/BylawsCore/Codebase/indexedFindings(of:modules:unitOutputFiles:location:filePath:line:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/indexedViolations(of:modules:unitOutputFiles:sourceLocation:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/projectIndex(modules:unitOutputFiles:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/conformers(of:modules:unitOutputFiles:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/directConformers(of:modules:unitOutputFiles:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/references(to:modules:unitOutputFiles:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/definitions(of:modules:unitOutputFiles:)>
- <doc:/BylawsIndex/BylawsCore/Codebase/occurrences(of:modules:unitOutputFiles:)>

### Errors

- ``ProjectIndexError``
- ``IndexedLayeringError``

### Index values

- ``/BylawsIndexStore/ProjectIndex``
- ``/BylawsIndexStore/IndexReference``
- ``/BylawsIndexStore/IndexSymbol``
- ``/BylawsIndexStore/SymbolRole``
