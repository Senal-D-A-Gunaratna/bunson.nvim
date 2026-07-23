local M = {}

local defaults = {
    patch_version_lookup = false,
    bun_cmd = "bun",
}

--- Restore all mason.nvim npm modules to their original (unpatched) state.
function M.restore()
    require("bunson.state").restore()
end

---@param opts? { patch_version_lookup?: boolean, bun_cmd?: string }
function M.setup(opts)
    opts = vim.tbl_deep_extend("keep", opts or {}, defaults)
    require("bunson.state").set_opts(opts)

    -- Check that the top-level mason module is loaded (it is placed into
    -- package.loaded as soon as require("mason").setup() runs, unlike the
    -- internal installer submodule which is only required lazily during an
    -- actual install).
    local ok, _ = pcall(require, "mason")
    if not ok then
        vim.notify(
            "bunson.nvim: mason.nvim is not installed or cannot be loaded. "
                .. "Add `dependencies = { 'mason-org/mason.nvim' }` to your bunson.nvim lazy.nvim spec.",
            vim.log.levels.ERROR
        )
        return
    end

    local state = require "bunson.state"

    -- Guard with both state flags so a future edit that clears one without
    -- the other can't silently double-patch or never-patch.
    if state.is_patched() then
        return
    end

    -- require() is always safe here: it either loads the file (first call)
    -- or returns the cached copy from package.loaded (subsequent calls).
    -- We wrap it in pcall because this is a private internal module that
    -- mason.nvim could rename or restructure without notice.
    local ok_npm, npm_manager = pcall(require, "mason-core.installer.managers.npm")
    if not ok_npm or type(npm_manager) ~= "table" then
        vim.notify(
            "bunson.nvim: failed to load mason-core.installer.managers.npm. "
                .. "This is a private mason.nvim internal module — it may have moved or been renamed. "
                .. "Please update bunson.nvim or file an issue.",
            vim.log.levels.ERROR
        )
        return
    end

    local installer = require "bunson.installer"
    local installer_originals = installer.apply(npm_manager, opts)
    state.set_originals("installer", installer_originals)

    -- Optional: patch version lookup provider
    --
    -- Same lazy-load caveat as the manager module: mason.providers.client.npm
    -- is only required on demand during a version lookup, so we
    -- require() it directly rather than checking package.loaded.
    --
    -- Instead of shelling out to `bun x npm view` (which would silently pull
    -- in the real npm package via bunx, defeating the point of a no-npm
    -- installer), we query the npm registry API directly with an HTTP GET
    -- via mason-core's built-in fetch utility. This avoids requiring any
    -- package manager binary for read-only metadata lookups.
    if opts.patch_version_lookup then
        local ok_client, npm_client = pcall(require, "mason.providers.client.npm")
        if ok_client and type(npm_client) == "table" then
            local version_lookup = require "bunson.version_lookup"
            local version_originals = version_lookup.apply(npm_client, opts)
            state.set_originals("version_lookup", version_originals)
        else
            vim.notify(
                "bunson.nvim: patch_version_lookup=true but mason.providers.client.npm not found. "
                    .. "This private internal module may have moved; skipping version lookup patch.",
                vim.log.levels.WARN
            )
        end
    end

    require("bunson.node_shim").ensure(opts)

    state.mark_patched()
end

return M
