-- OpenRouter Collector for Agent Usage Monitor
-- Reads API key from ~/.local/share/opencode/auth.json and calls OpenRouter API
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local function now_ms()
    return os.time() * 1000
end

-- Get HOME safely (os.getenv may not be available in the Noctalia sandbox)
local function home_dir()
    local home = os.getenv and os.getenv("HOME")
    if not home or home == "" then
        home = os.getenv and os.getenv("USERPROFILE") or ""
    end
    if not home or home == "" then
        home = "/home/" .. ((os.getenv and os.getenv("USER")) or "roddy")
    end
    return home
end

local function expand_path(path)
    if path:sub(1, 1) == "~" then
        return home_dir() .. path:sub(2)
    end
    return path
end

local function read_auth_json()
    local auth_path = expand_path("~/.local/share/opencode/auth.json")
    local content, err = noctalia.readFile(auth_path)
    if not content then return nil, err end
    local ok, data = pcall(noctalia.json.decode, content)
    if not ok then return nil, "JSON parse error: " .. tostring(data) end
    return data, nil
end

local function fetch_openrouter_usage(api_key, callback)
    -- OpenRouter API: GET https://openrouter.ai/api/v1/auth/key
    -- Returns: { data: { label, limit, usage, is_free_tier, ... } }
    local cmd = "curl -s -H \"Authorization: Bearer " .. api_key
        .. "\" -H \"Accept: application/json\" https://openrouter.ai/api/v1/auth/key"
    noctalia.runAsync(cmd, function(result)
        if not result or result.code ~= 0 then
            callback(nil, "curl failed: " .. tostring(result and result.stderr or "unknown"))
            return
        end
        local ok, data = pcall(noctalia.json.decode, result.stdout)
        if not ok then callback(nil, "JSON parse error: " .. tostring(data)) return end
        callback(data, nil)
    end)
end

local function fetch_openrouter_models(api_key, callback)
    -- OpenRouter API: GET https://openrouter.ai/api/v1/models
    local cmd = "curl -s -H \"Authorization: Bearer " .. api_key
        .. "\" -H \"Accept: application/json\" https://openrouter.ai/api/v1/models"
    noctalia.runAsync(cmd, function(result)
        if not result or result.code ~= 0 then
            callback(nil, "curl failed: " .. tostring(result and result.stderr or "unknown"))
            return
        end
        local ok, data = pcall(noctalia.json.decode, result.stdout)
        if not ok then callback(nil, "JSON parse error: " .. tostring(data)) return end
        callback(data, nil)
    end)
end

local M = {
    name = "openrouter",
    default_config = {
        enabled = true,
        api_key_env = "OPENROUTER_API_KEY", -- fallback if not in auth.json
    },
}

function M.validate_config(cfg)
    if not cfg then return true, nil end
    if cfg.api_key_env and type(cfg.api_key_env) ~= "string" then
        return false, "api_key_env must be string"
    end
    return true, nil
end

-- Synchronous stub kept for contract/tests; runtime uses collect_async (network)
function M.collect(config)
    return nil, "OpenRouter collector is network-backed; use collect_async"
end

function M.collect_async(config, callback)
    config = config or M.default_config

    -- Try to get API key from opencode auth.json first
    local auth_data, err = read_auth_json()
    local api_key = nil

    if auth_data and auth_data.openrouter and auth_data.openrouter.key then
        api_key = auth_data.openrouter.key
    elseif config.api_key_env then
        api_key = os.getenv and os.getenv(config.api_key_env)
    end

    if not api_key then
        callback(nil, "OpenRouter API key not found in auth.json or env")
        return
    end

    -- Fetch usage/credits
    fetch_openrouter_usage(api_key, function(key_data, fetch_err)
        if not key_data then
            callback(nil, "Failed to fetch OpenRouter key data: " .. tostring(fetch_err))
            return
        end

        -- Parse key data
        local key_info = key_data.data or key_data
        local limit = key_info.limit or 0
        local usage = key_info.usage or 0
        local is_free = key_info.is_free_tier or false
        local label = key_info.label or "OpenRouter"

        -- Calculate remaining
        local remaining = limit > 0 and (limit - usage) or 0
        local pct = limit > 0 and math.floor((usage / limit) * 100) or 0

        -- Fetch models to show which free models are available
        fetch_openrouter_models(api_key, function(models_data)
            local free_models = {}
            if models_data and models_data.data then
                for _, model in ipairs(models_data.data) do
                    if model.pricing and model.pricing.prompt == "0" and model.pricing.completion == "0" then
                        table.insert(free_models, model.id)
                    end
                end
            end

            -- Build snapshot
            local snapshot = {
                version = 1,
                timestamp = now_ms(),
                agent = "openrouter",
                plan = is_free and "Free Tier" or "Paid",
                quota = {
                    used = usage,
                    limit = limit,
                    reset_ms = 0, -- OpenRouter doesn't provide reset time in this endpoint
                    period = "month",
                },
                balance = limit > 0 and {
                    credits = remaining,
                    currency = "USD",
                    estimated = false,
                } or nil,
                speaking = false,
                tokens_today = 0, -- Not available from this endpoint
                tokens_by_model = {}, -- Would need /api/v1/usage endpoint with date range
                tokens_by_type = nil,
                tokens_daily = {},
                limits = {},
            }

            -- Add limit info
            if limit > 0 then
                table.insert(snapshot.limits, {
                    name = "Monthly credits",
                    used = usage,
                    limit = limit,
                    reset_ms = 0,
                    percent = pct,
                })
            end

            -- Add free models as note
            if #free_models > 0 then
                snapshot.free_models = free_models
                snapshot.note = "Free models available: " .. table.concat(free_models, ", ")
            end

            callback(snapshot, nil)
        end)
    end)
end

return M