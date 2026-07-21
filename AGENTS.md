# Commit discipline

You MUST commit every logical step before moving on. Do not batch multiple changes into a single commit.

## When to commit

You MUST run `git add -A && git commit -m "message"` after completing any of the following:

- Editing a file (create, modify, delete)
- Running a command that produces a meaningful result
- Completing a subtask or subgoal
- Any point where `git status` shows unstaged or uncommitted changes and you are about to start something new

## Commit message rules

- Use the **conventional commits** format: `type(scope): description`
- Keep the description under 72 characters
- Use the imperative mood ("add feature" not "added feature")
- Types: `feat`, `fix`, `refactor`, `style`, `docs`, `BRAKING_CHANGES!`, `test`, `chore`, `perf`

## Verification

Before each commit, run `git diff --stat` to verify only intended files are staged. Never commit generated files, secrets, or unrelated changes.

## Exceptions

Only skip a commit if the change is trivially revertible (e.g., a single `git checkout .` would undo it) AND you are immediately proceeding to the next step in the same train of thought.

# node-shim regression verification

When `node` is not on PATH, bunson.setup() creates a shell wrapper at
`<install_root_dir>/bin/node` that delegates to `bun`, so that
`#!/usr/bin/env node` shebangs in LSP servers resolve correctly.

## Manual verify

```bash
# 1. Confirm node is absent from PATH
which node  # should fail
which bun   # should succeed

# 2. Confirm LSPs currently fail with "env: node: No such file or directory"
~/.local/share/nvim/mason/bin/cspell-lsp --help
# expected: "env: 'node': No such file or directory"

# 3. Simulate what bunson.setup() does – create the node shim
MASON_BIN=~/.local/share/nvim/mason/bin
mkdir -p "$MASON_BIN"
cat > "$MASON_BIN/node" << 'SCRIPT'
#!/bin/sh
exec "$(which bun)" "$@"
SCRIPT
chmod 755 "$MASON_BIN/node"

# 4. Confirm LSPs now work (same PATH as nvim's LSP client would have)
PATH="$MASON_BIN:$PATH" ~/.local/share/nvim/mason/bin/cspell-lsp --help
# expected: no "env: node" error, LSP starts (may error about missing transport)
```

## Automated check

```lua
-- After require("bunson").setup():
if vim.fn.executable("node") == 0 then
    local mason_settings = require("mason.settings")
    local node_shim = mason_settings.current.install_root_dir .. "/bin/node"
    assert(vim.fn.executable(node_shim) == 1,
        "bunson should create " .. node_shim .. " when node is not on PATH")
end

-- After require("bunson").restore():
-- (simulate by calling it right after setup above)
if vim.fn.executable("node") == 0 then
    local mason_settings = require("mason.settings")
    local node_shim = mason_settings.current.install_root_dir .. "/bin/node"
    assert(vim.fn.filereadable(node_shim) == 0,
        "bunson should remove " .. node_shim .. " on restore()")
end
```
