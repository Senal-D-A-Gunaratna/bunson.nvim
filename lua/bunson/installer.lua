local M = {}

---@async
---@param npm_manager table
---@param opts { bun_cmd: string }
---@return { init: fun(...), install: fun(...), uninstall: fun(...) }
function M.apply(npm_manager, opts)
    local Result = require "mason-core.result"
    local installer = require "mason-core.installer"
    local log = require "mason-core.log"
    local SystemPackage = require "mason-core.system-package"

    local originals = {
        init = npm_manager.init,
        install = npm_manager.install,
        uninstall = npm_manager.uninstall,
    }

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

    return originals
end

---@param npm_manager table
---@param originals { init: fun(...), install: fun(...), uninstall: fun(...) }
function M.revert(npm_manager, originals)
    if originals.init then
        npm_manager.init = originals.init
    end
    if originals.install then
        npm_manager.install = originals.install
    end
    if originals.uninstall then
        npm_manager.uninstall = originals.uninstall
    end
end

return M
