# ``BylawsIndexStore``

Read symbols and references from a Swift build's index store.

## Overview

You can use `BylawsIndexStore` to query a Swift build's index directly from your
own tool. For rules on a `Codebase`, use the `BylawsIndex` product instead.

Run the queries on macOS or Linux with a Swift toolchain installed. For an iOS
project, use a macOS test target or command-line tool to check the app's build.

A SwiftPM debug build writes index data by default, while a release build needs
`--enable-index-store`. If your build uses a location outside those searched
by ``IndexStoreLocation``, set `BYLAWS_INDEX_STORE` to the store's path.

Add the `BylawsIndexStore` product to your target. This example opens a
package's index store and finds types that conform to `Repository`:

```swift
import Foundation
import BylawsIndexStore

let packageRoot = FileManager.default.currentDirectoryPath
let path = try IndexStoreLocation.path(forPackageAt: packageRoot)
let store = try IndexStore(path: path)
let index = try ProjectIndex(store: store, modules: ["Domain", "Data"])
let conformers = index.conformers(of: "Repository")
```

## Topics

### Querying the index

- ``ProjectIndex``
- ``IndexReference``
- ``IndexSymbol``
- ``SymbolRole``

### Reading a store

- ``IndexStoreLocation``
- ``IndexStore``
- ``IndexUnit``
- ``IndexRecord``
- ``IndexOccurrence``
- ``IndexRelation``
- ``IndexStoreError``
