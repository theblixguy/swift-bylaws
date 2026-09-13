# Bylaws for Neovim

Bylaws reports violations of your architectural rules as you edit Swift files.

You need Neovim 0.11 or later.

## Install

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

Add this repository to your plugin manager's plugin list using the following
entry for [lazy.nvim]:

```lua
{ "theblixguy/swift-bylaws", lazy = false }
```

After your plugin manager installs the repository, restart Neovim and open a
Swift file to check your project's rules. The project folder must contain
`Bylaws.swift`, `Package.swift` or `.git`.

If you haven't written rules yet, try the [module boundary example].

## Configure the client

You can use `vim.lsp.config` after the plugin setup to change its settings. To
wait 300 ms after the last keystroke before checking again, use:

```lua
vim.lsp.config("bylaws", {
  init_options = {
    refreshDelayMilliseconds = 300,
  },
})
```

Restart Neovim to apply the setting.

| Option in `init_options`   | Purpose                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `rules`                    | Set the paths to your rules files relative to the workspace folder. Leave the list empty to find `Bylaws.swift` files automatically. |
| `only`                     | Run only these rule IDs. Leave the list empty to run all rules.                                                                      |
| `skip`                     | Skip these rule IDs.                                                                                                                 |
| `baseline`                 | Set the baseline file's path relative to the workspace folder. Omit this option to find `Bylaws.baseline.swift` files automatically. |
| `refreshDelayMilliseconds` | Set how long to wait after the last keystroke before checking again. The default is 0 ms.                                            |

These settings apply to every project, so leave `rules` unset if your projects
keep their rules in different locations.

If Neovim cannot find the server on `PATH`, add
`cmd = { "/path/to/bylaws-lsp" }` beside `init_options` in the configuration
table and replace the path with the installed executable. Use the [Neovim LSP
guide] to inspect active clients and the [shared troubleshooting
guide][If diagnostics do not appear] for problems with the rules.

[lazy.nvim]: https://lazy.folke.io/spec
[module boundary example]: ../README.md#check-your-first-rule
[Neovim LSP guide]: https://neovim.io/doc/user/lsp.html
[If diagnostics do not appear]: ../README.md#if-diagnostics-do-not-appear
