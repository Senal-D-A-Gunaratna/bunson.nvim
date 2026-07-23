local M = {}

local originals = {}
local patched = false
local opts = nil

function M.is_patched()
    return patched
end

---@param category string "installer" | "version_lookup"
---@param tbl table<string, fun(...)>
function M.set_originals(category, tbl)
    originals[category] = tbl
end

---@param category string
---@return table|nil
function M.get_originals(category)
    return originals[category]
end

---@param category string
function M.has_originals(category)
    return originals[category] ~= nil
end

function M.clear_originals()
    originals = {}
    patched = false
end

---@param new_opts table
function M.set_opts(new_opts)
    opts = new_opts
end

---@return table|nil
function M.get_opts()
    return opts
end

function M.mark_patched()
    patched = true
end

--- Restore all mason.nvim npm modules to their original (unpatched) state.
function M.restore()
    local npm_manager = package.loaded["mason-core.installer.managers.npm"]
    if npm_manager and originals.installer then
        require("bunson.installer").revert(npm_manager, originals.installer)
    end

    local npm_client = package.loaded["mason.providers.client.npm"]
    if npm_client and originals.version_lookup then
        require("bunson.version_lookup").revert(npm_client, originals.version_lookup)
    end

    require("bunson.node_shim").remove()

    M.clear_originals()
end

return M
