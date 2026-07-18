local M = {}

local defaults = {
    patch_version_lookup = false,
    bun_cmd = "bun",
}

--- Invariant: state.patched is true iff M._originals is non-nil.
--- Both must be set/cleared together so no code path can update one
--- without the other.
local state = {
    patched = false,
}

--- Restore all mason.nvim npm modules to their original (unpatched) state.
function M.restore()
    local npm_manager = package.loaded["mason-core.installer.managers.npm"]
    if npm_manager and M._originals then
        if M._originals.init then
            npm_manager.init = M._originals.init
        end
        if M._originals.install then
            npm_manager.install = M._originals.install
        end
        if M._originals.uninstall then
            npm_manager.uninstall = M._originals.uninstall
        end
    end

    local npm_client = package.loaded["mason.providers.client.npm"]
    if npm_client and M._originals then
        if M._originals.get_latest_version then
            npm_client.get_latest_version = M._originals.get_latest_version
        end
        if M._originals.get_all_versions then
            npm_client.get_all_versions = M._originals.get_all_versions
        end
    end

    M._originals = nil
    state.patched = false
end

---@param opts? { patch_version_lookup?: boolean, bun_cmd?: string }
function M.setup(opts)
    opts = vim.tbl_deep_extend("keep", opts or {}, defaults)

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

    -- Guard with both state flags so a future edit that clears one without
    -- the other can't silently double-patch or never-patch.
    if state.patched and M._originals then
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

    M._originals = {
        init = npm_manager.init,
        install = npm_manager.install,
        uninstall = npm_manager.uninstall,
    }

    local Result = require "mason-core.result"
    local installer = require "mason-core.installer"
    local log = require "mason-core.log"
    local SystemPackage = require "mason-core.system-package"

    -- Patch init()
    -- Original behavior: spawns `npm init --yes --scope=mason`, then writes .npmrc with
    -- install-strategy=shallow (npm >=9) or global-style=true (npm <9) to force a flat install layout.
    -- Bun variant: no-op. bun add auto-creates a package.json if none exists (tested behavior),
    -- and bun's default node_modules layout is already flat — no config equivalent needed.
    ---@async
    npm_manager.init = function()
        log.debug "bunson: init (no-op — bun add creates package.json automatically)"
        local ctx = installer.context()
        return Result.try(function(_try)
            ctx.stdio_sink:stdout "Skipped npm init (bun add handles package.json creation).\n"
        end)
    end

    -- Patch install()
    -- Original behavior: spawns `npm install "<pkg>@<version>" [extra_packages] [install_extra_args]`
    -- Bun variant: spawns `bun add "<pkg>@<version>" [extra_packages] [install_extra_args]`
    -- bun add saves to package.json (same as npm install in npm 5+) — fine for mason's isolated install dir.
    ---@async
    ---@param pkg string
    ---@param version string
    ---@param install_opts? { extra_packages?: string[], install_extra_args?: string[] }
    npm_manager.install = function(pkg, version, install_opts)
        install_opts = install_opts or {}
        log.fmt_debug("bunson: install %s %s %s", pkg, version, install_opts)
        local ctx = installer.context()
        ctx:require(SystemPackage.sfw)
        ctx.stdio_sink:stdout(("Installing npm package %s@%s via bun…\n"):format(pkg, version))
        return ctx.spawn[opts.bun_cmd] {
            "add",
            ("%s@%s"):format(pkg, version),
            install_opts.extra_packages or vim.NIL,
            install_opts.install_extra_args or vim.NIL,
            firewall = true,
        }
    end

    -- Patch uninstall()
    -- Original behavior: spawns `npm uninstall <pkg>`
    -- Bun variant: spawns `bun remove <pkg>`
    ---@async
    ---@param pkg string
    npm_manager.uninstall = function(pkg)
        local ctx = installer.context()
        ctx.stdio_sink:stdout(("Uninstalling npm package %s via bun…\n"):format(pkg))
        return ctx.spawn[opts.bun_cmd] { "remove", pkg }
    end

    -- bin_path() is NOT patched: bun produces the same node_modules/.bin/<exec> layout as npm.

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
            M._originals.get_latest_version = npm_client.get_latest_version
            M._originals.get_all_versions = npm_client.get_all_versions

            local fetch = require "mason-core.fetch"
            local _ = require "mason-core.functional"
            local semver = require "mason-core.semver"

            -- Original: spawns `npm view --json <pkg>@latest`
            -- Replacement: GET https://registry.npmjs.org/<pkg>/latest
            -- The npm registry's /latest endpoint returns the same
            -- {name, version, ...} shape as `npm view --json pkg@latest`.
            npm_client.get_latest_version = function(pkg)
                return fetch("https://registry.npmjs.org/" .. pkg .. "/latest")
                    :map_catching(vim.json.decode)
                    :map(_.pick { "name", "version" })
            end

            -- Original: spawns `npm view --json <pkg> versions`
            -- Replacement: GET https://registry.npmjs.org/<pkg>
            -- then extract version keys and sort descending by semver.
            --
            -- The raw registry JSON's `versions` object has no guaranteed key
            -- order, so we must sort explicitly. Unlike the old `npm view`
            -- approach (which returned an array npm had already sorted), we
            -- use mason-core.semver's comparator for correct numerical major/
            -- minor/patch ordering, not lexicographic string comparison which
            -- would put 10.0.0 before 2.0.0.
            npm_client.get_all_versions = function(pkg)
                return fetch("https://registry.npmjs.org/" .. pkg)
                    :map_catching(vim.json.decode)
                    :map(function(data)
                        local versions = {}
                        for v, _ in pairs(data.versions) do
                            table.insert(versions, v)
                        end
                        table.sort(versions, function(a, b)
                            local ok_a, sem_a = pcall(semver.new, a)
                            local ok_b, sem_b = pcall(semver.new, b)
                            if ok_a and ok_b then
                                return sem_b < sem_a
                            end
                            log.fmt_debug(
                                "bunson: failed to parse semver for %q or %q, falling back to string comparison",
                                a,
                                b
                            )
                            return a > b
                        end)
                        return versions
                    end)
            end
        else
            vim.notify(
                "bunson.nvim: patch_version_lookup=true but mason.providers.client.npm not found. "
                    .. "This private internal module may have moved; skipping version lookup patch.",
                vim.log.levels.WARN
            )
        end
    end

    state.patched = true
end

return M
