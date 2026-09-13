# Bylaws for Emacs

Bylaws reports violations of your architectural rules as you edit Swift files.

You can use it with Emacs 29.1 or later and `lsp-mode` 10.0.1 or later.

## Install

Install Bylaws with Homebrew on macOS or Linux:

```sh
brew install theblixguy/tap/bylaws
```

If you haven't set up `lsp-mode`, follow its [installation guide] first.
Download [lsp-bylaws.el] to a directory on your `load-path` and load it from
your Emacs configuration:

```elisp
(require 'lsp-bylaws)
(add-hook 'swift-mode-hook #'lsp-deferred)
```

Use the hook for your Swift major mode if it differs from `swift-mode-hook`.
If you have a hook that calls `lsp-deferred`, keep it instead of adding another.

Restart Emacs and open a Swift file in your project to check your `Bylaws.swift`
rules. You can try the [module boundary example] if you haven't written any yet.

## Change the settings

You can change the Bylaws options through
`M-x customize-group RET lsp-bylaws RET` or set them in your Emacs
configuration. To wait 300 ms after the last keystroke before checking again,
use:

```elisp
(setq lsp-bylaws-refresh-delay-milliseconds 300)
```

Run `M-x lsp-workspace-restart` to apply the change.

| Option                                  | Purpose                                                                                                                              |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `lsp-bylaws-server-command`             | Set the command or absolute path used to start `bylaws-lsp`.                                                                         |
| `lsp-bylaws-rules`                      | Set the paths to your rules files relative to the workspace folder. Leave the list empty to find `Bylaws.swift` files automatically. |
| `lsp-bylaws-only`                       | Run only these rule IDs. Leave the list empty to run all rules.                                                                      |
| `lsp-bylaws-skip`                       | Skip these rule IDs.                                                                                                                 |
| `lsp-bylaws-baseline`                   | Set the baseline file's path relative to the workspace folder. Leave it unset to find `Bylaws.baseline.swift` files automatically.   |
| `lsp-bylaws-refresh-delay-milliseconds` | Set how long to wait after the last keystroke before checking again. The default is 0 ms.                                            |

These values apply to every project, so leave `lsp-bylaws-rules` unset if your
projects keep their rules in different locations.

If Emacs cannot find the server, set `lsp-bylaws-server-command` to the
executable's absolute path. For problems with the rules, see [If diagnostics do
not appear].

[installation guide]: https://emacs-lsp.github.io/lsp-mode/page/installation/
[lsp-bylaws.el]: lsp-bylaws.el
[module boundary example]: ../README.md#check-your-first-rule
[If diagnostics do not appear]: ../README.md#if-diagnostics-do-not-appear
