local M = {}

function M.check()
    vim.health.start "bunson.nvim"

    local ok_mason, _ = pcall(require, "mason")
    if ok_mason then
        vim.health.ok "mason.nvim is installed"
    else
        vim.health.error(
            "mason.nvim is not installed or cannot be loaded. "
                .. "Add `dependencies = { 'mason-org/mason.nvim' }` to your bunson.nvim lazy.nvim spec."
        )
        return
    end

    local state = require "bunson.state"
    local configured_opts = state.get_opts()
    local bun_cmd = (configured_opts or {}).bun_cmd or "bun"
    if not configured_opts then
        vim.health.info "setup() has not been called yet — using default bun_cmd='bun', not user config"
    end
    local bun_path = vim.fn.exepath(bun_cmd)
    if bun_path and bun_path ~= "" then
        vim.health.ok(("bun found at %s"):format(bun_path))
    else
        vim.health.error(("bun_cmd '%s' not found on $PATH"):format(bun_cmd))
    end

    local node_found = vim.fn.executable "node" == 1
    if node_found then
        local node_exe = vim.fn.exepath "node"
        vim.health.info(
            ("system node found at %s"
                .. " — node shim will not be created, npm-published packages run on real node."):format(node_exe)
        )
    else
        vim.health.info "no system node found — bunson will create a node shim delegating to bun."
    end

    if not node_found then
        local ok_settings, mason_settings = pcall(require, "mason.settings")
        if ok_settings then
            local node_shim = mason_settings.current.install_root_dir .. "/bin/node"
            if vim.fn.filereadable(node_shim) == 0 then
                vim.health.info "shim not yet created (created on first setup() call if node stays absent)"
            elseif vim.fn.executable(node_shim) == 1 then
                vim.health.ok(("node shim active at %s"):format(node_shim))
            else
                vim.health.error(
                    ("node shim exists but is not executable at %s"
                        .. " — LSP servers using #!/usr/bin/env node will fail with exit 127."
                        .. " Delete the file and restart nvim to regenerate it."):format(node_shim)
                )
            end
        end
    end

    if state.is_patched() then
        vim.health.ok "mason's npm manager is currently patched to use bun"
    else
        vim.health.warn "not currently patched — call require('bunson').setup() in your config"
    end

    if state.has_originals "version_lookup" then
        vim.health.ok "patch_version_lookup is enabled — version queries use npm registry API directly"
    else
        vim.health.info "\"npm view\" lookups still shell out to real npm"
    end
end

return M
