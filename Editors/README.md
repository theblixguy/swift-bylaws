# Editor setup

You can run your Bylaws rules as you edit Swift files, including changes you
haven't saved.

Choose your editor's guide to install Bylaws and set it up on macOS or Linux:

- [VS Code and Cursor]
- [Zed]
- [Neovim]
- [Emacs]

You can use the same rules and baseline as the CLI. Rules that need the
compiler's index must run separately through the CLI or tests after a build.

## Check your first rule

You can try the [module boundary example] to see Bylaws report and clear a
violation as you add and remove a forbidden import from Checkout:

1. Change the example's paths and module names to match your project and save it
   in `Bylaws.swift` at the project root.
2. Open the project folder in your editor and then a Swift file in Checkout.
3. Add `import Persistence`. Bylaws reports the import before you save.
4. Remove the import and wait for the diagnostic to clear.

## If diagnostics do not appear

Check that the server is installed:

```sh
bylaws-lsp --version
```

If your shell cannot find `bylaws-lsp`, check the Homebrew installation. Your
editor may use a different `PATH` from your terminal, so set the server's
absolute path in the editor settings if the command only works in the terminal.

Next, save your changes and run the rules from the project root:

```sh
bylaws lint
```

If the command reports an error in a rules file, fix that error before checking
the editor again. If it reports a violation that the editor misses, check that
both use the same project root, rules and baselines and that the `only` and
`skip` settings include the rule you want to check. After changing the settings,
restart the Bylaws language server or reload VS Code or Cursor.

If an edit introduces a syntax error, Bylaws keeps the previous diagnostics
until you correct the syntax.

[VS Code and Cursor]: VSCode/README.md
[Zed]: Zed/README.md
[Neovim]: Neovim/README.md
[Emacs]: Emacs/README.md
[module boundary example]: ../README.md#enforce-a-module-boundary
