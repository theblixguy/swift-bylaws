# Bylaws for VS Code and Cursor

Bylaws reports violations of your architectural rules as you edit Swift files.

## Install

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

In the Extensions view, search for `theblixguy.bylaws` and install **Bylaws**.

If your editor's registry does not list Bylaws, you can download `bylaws.vsix`
from the [GitHub editor release] and install it through **Extensions: Install
from VSIX** in the command palette.

Open your project folder and trust the workspace to enable the extension, then
open a Swift file to check your `Bylaws.swift` rules. If you haven't written a
rule yet, try the [module boundary example].

## Configure the rules

Bylaws finds `Bylaws.swift` and `Bylaws.baseline.swift` files automatically. If
you keep your rules in a test target under another path, you can select that
file in `.vscode/settings.json`:

```json
{
  "bylaws.rules": ["Tests/AppTests/Bylaws.swift"]
}
```

| Setting                           | Purpose                                                                                                              |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `bylaws.serverPath`               | Set the path to `bylaws-lsp`. Leave it empty to search `PATH` and the standard Homebrew locations.                   |
| `bylaws.rules`                    | Set the paths to your rules files relative to the workspace folder. Leave the list empty to find them automatically. |
| `bylaws.only`                     | Run only these rule IDs. Leave the list empty to run all rules.                                                      |
| `bylaws.skip`                     | Skip these rule IDs.                                                                                                 |
| `bylaws.baseline`                 | Set the baseline file's path relative to the workspace folder. Leave it empty to find baselines automatically.       |
| `bylaws.refreshDelayMilliseconds` | Set how long to wait after the last keystroke before checking again. The default is 0 ms.                            |

Reload the editor after changing these settings. Bylaws uses the first folder's
rules and settings in a workspace with several folders, so open projects in
separate windows if they need different Bylaws settings.

For help with a server that won't start or a violation that doesn't appear, see
[If diagnostics do not appear].

[GitHub editor release]: https://github.com/theblixguy/swift-bylaws/releases
[module boundary example]: ../README.md#check-your-first-rule
[If diagnostics do not appear]: ../README.md#if-diagnostics-do-not-appear
