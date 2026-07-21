local M = {}

---@param opts { bun_cmd: string }
function M.ensure(opts)
    local log = require "mason-core.log"

    -- If 'node' is not on PATH, create a node wrapper in mason/bin/ that
    -- delegates to bun.  mason.setup() already prepends mason/bin/ to
    -- vim.env.PATH, so any process spawned by nvim (including LSP servers)
    -- will find this wrapper when the kernel resolves the #!/usr/bin/env node
    -- shebang in JavaScript bin files.
    --
    -- This avoids the "exit code 127 (command not found)" error at LSP launch
    -- on systems where only bun (not node) is installed.
    if vim.fn.executable "node" == 0 then
        local ok_settings, mason_settings = pcall(require, "mason.settings")
        if ok_settings then
            local mason_bin = mason_settings.current.install_root_dir .. "/bin"
            local node_shim = mason_bin .. "/node"
            if vim.fn.executable(node_shim) == 0 then
                local bun_path = vim.fn.exepath(opts.bun_cmd)
                if bun_path and bun_path ~= "" then
                    vim.fn.mkdir(mason_bin, "p")
                    local ok, err = io.open(node_shim, "w")
                    if ok then
                        ok:write(("#!/bin/sh\nexec %q \"$@\"\n"):format(bun_path))
                        ok:close()
                        vim.fn.setfperm(node_shim, "rwxr-xr-x")
                        if vim.fn.executable(node_shim) == 1 then
                            log.fmt_debug("bunson: created node shim at %s -> %s", node_shim, bun_path)
                        else
                            log.warn(
                                ("bunson: wrote node shim to %s but it is not executable after chmod. "
                                    .. "LSPs relying on #!/usr/bin/env node will fail with exit 127."):format(
                                    node_shim
                                )
                            )
                        end
                    else
                        log.warn(
                            ("bunson: failed to create node shim at %s: %s. "
                                .. "LSPs relying on #!/usr/bin/env node will fail with exit 127."):format(
                                node_shim,
                                err
                            )
                        )
                    end
                end
            end
        end
    end
end

return M
