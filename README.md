# bunson.nvim

## Status

Tested end-to-end (install + LSP attach + cold-start survival) with
[cspell-lsp](https://github.com/streetsidesoftware/cspell) (LSP server) and
[prettier](https://github.com/prettier/prettier) (formatter with native platform
binary resolution), on Arch Linux. Has zero automated test coverage.

When `node` is not found on `$PATH`, bunson.nvim creates a shell wrapper at
`<mason_install_root>/bin/node` that delegates to `bun`, so npm-published
packages with `#!/usr/bin/env node` shebangs still resolve.

A companion plugin for [mason.nvim](https://github.com/mason-org/mason.nvim) that
routes npm package installs through **bun** instead of **npm**.

## Why?

`bun add` is significantly faster than `npm install` for installing npm packages.
Since mason.nvim installs hundreds of LSP servers, linters, and formatters from
npm, using bun cuts install time dramatically on a fresh setup.

mason.nvim's maintainers have (reasonably) declined to add native bun support
upstream, as it would introduce a dependency on an external toolchain with
overlapping but not identical semantics to npm.

## How it works

bunson.nvim **monkeypatches** mason.nvim's internal npm manager module
(`mason-core.installer.managers.npm`) at runtime, replacing the `init`,
`install`, and `uninstall` functions with bun equivalents.

This is the same technique used by
[mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim)
and
[mason-tool-installer.nvim](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim)
to extend mason.nvim without forking it.

The patches are applied to the module tables cached in `package.loaded`, which
every mason.nvim internal that require the same module path shares. No files are
modified.

## Requirements

- Neovim >= 0.7.0
- [mason.nvim](https://github.com/mason-org/mason.nvim)
- `bun` installed and on `$PATH`
- **Platform**: Linux (tested); macOS should work but is unverified; Windows is
  not currently supported (node shim is POSIX shell only).

## Installation (lazy.nvim)

```lua
{
    "Senal-D-A-Gunaratna/bunson.nvim",
    dependencies = {
        "mason-org/mason.nvim",
    },
    config = function()
        require("bunson").setup()
    end,
}
```

The `dependencies` key ensures mason.nvim loads before bunson.nvim, which is
required since bunson.nvim patches mason.nvim's already-loaded modules.

## Configuration

`require("bunson").setup(opts)` accepts an optional table:

```lua
require("bunson").setup({
    -- Whether to also patch mason's npm version-lookup client
    -- (npm view --json) to use bun's package runner instead.
    -- Default: false (npm view works fine alongside bun-based installs).
    patch_version_lookup = false,

    -- The bun binary name/path. Change if bun is installed under a
    -- different name or at a custom path.
    bun_cmd = "bun",
})
```

## Reverting

Call `require("bunson").restore()` to restore mason.nvim's original npm
functions. Useful for A/B testing or if bun-based installs misbehave for a
specific package.

## Caveats

bunson.nvim patches **private** Lua modules internal to mason.nvim
(`mason-core.installer.managers.npm` and optionally
`mason.providers.client.npm`). These modules are not part of mason.nvim's
public API. Future mason.nvim releases may refactor or rename them without a
semver-major bump, which could break bunson.nvim silently.

If bunson.nvim stops working after a mason.nvim update, check
[mason.nvim's changelog](https://github.com/mason-org/mason.nvim/releases) for
internal module changes and file an issue.

## Verified packages

The following packages have been verified end-to-end (install via bun, LSP/tool
attach, cold-start survival) on Arch Linux:

- **[cspell-lsp](https://github.com/streetsidesoftware/cspell)** — LSP server,
  pure JavaScript, verifies that bun resolves `#!/usr/bin/env node` shebangs via
  the node shim and that mason's bin-linking step produces a working symlink
  chain.
- **[prettier](https://github.com/prettier/prettier)** — Formatter with a native
  platform binary download step, verifies that bun handles platform-specific
  optional dependencies correctly.

Packages with `node-gyp` native addons, npm-specific `postinstall` hooks, or
deep scoped dependency trees remain unverified.

## License

MIT
