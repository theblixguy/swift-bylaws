# Bylaws for Zed

Bylaws reports violations of your architectural rules as you edit Swift files.

## Install

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

Install **Bylaws** from Zed's [Extensions view] and open the project folder
containing `Bylaws.swift`, then open a Swift file to check the rules.

If you haven't written rules yet, try the [module boundary example].

## Configure the server

To wait 300 ms after the last keystroke before checking again, add this setting
to your project's `.zed/settings.json`:

```json
{
  "lsp": {
    "bylaws": {
      "initialization_options": {
        "refreshDelayMilliseconds": 300
      }
    }
  }
}
```

Restart the language server to apply the setting.

| Option in `initialization_options` | Purpose                                                                                                                              |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `rules`                            | Set the paths to your rules files relative to the workspace folder. Leave the list empty to find `Bylaws.swift` files automatically. |
| `only`                             | Run only these rule IDs. Leave the list empty to run all rules.                                                                      |
| `skip`                             | Skip these rule IDs.                                                                                                                 |
| `baseline`                         | Set the baseline file's path relative to the workspace folder. Omit this option to find `Bylaws.baseline.swift` files automatically. |
| `refreshDelayMilliseconds`         | Set how long to wait after the last keystroke before checking again. The default is 0 ms.                                            |

If Zed cannot find `bylaws-lsp`, set `lsp.bylaws.binary.path` to the
executable's absolute path. For a Swift configuration with a custom
`language_servers` list, include `bylaws` in the list as described in Zed's
[language configuration guide].

For other problems, see [If diagnostics do not appear].

[Extensions view]: https://zed.dev/docs/extensions/installing-extensions
[module boundary example]: ../README.md#check-your-first-rule
[language configuration guide]: https://zed.dev/docs/configuring-languages
[If diagnostics do not appear]: ../README.md#if-diagnostics-do-not-appear
