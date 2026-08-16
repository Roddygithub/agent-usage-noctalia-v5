-- opencode Collector for Agent Usage Monitor
-- Reads ~/.config/opencode/usage.json
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

local M = {
    name = "opencode",
    default_config = {
        enabled = true,
        config_path = "~/.config/opencode/usage.json",
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Config Validation
-- ─────────────────────────────────────────────────────────────────────────────

function M.validate_config(cfg)
    if not cfg then return true, nil end
    if cfg.config_path and type(cfg.config_path) ~= "string" then
        return false, "config_path must be string"
    end
    return true, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Collection Function
-- ─────────────────────────────────────────────────────────────────────────────

function M.collect(config)
    config = config or M.default_config
    local path = config.config_path or "~/.config/opencode/usage.json"

    -- Expand tilde
    if path:sub(1, 1) == "~" then
        path = home_dir() .. path:sub(2)
    end

    -- Read file
    local content, err = noctalia.readFile(path)
    if not content then
        if err and err:match("not found") then
            return nil, "opencode usage file not found: " .. path
        end
        return nil, "Failed to read opencode usage file: " .. tostring(err)
    end

    -- Parse JSON
    local ok, data = pcall(noctalia.json.decode, content)
    if not ok then
        return nil, "Failed to parse opencode usage.json: " .. tostring(data)
    end

    -- Expected structure from opencode:
    -- {
    --   "plan": "Free|Pro|Max",
    --   "usage": { "tokens": 15000, "limit": 50000, "reset": 1692086400 },
    --   "models": { "gpt-4o": 30000, "gpt-4o-mini": 15000 },
    --   "speaking": false
    -- }

    local plan = data.plan or "Free"
    local usage = data.usage or {}
    local models = data.models or {}
    local speaking = data.speaking or false

    local tokens_used = usage.tokens or 0
    local tokens_limit = usage.limit or 0
    local reset_ts = usage.reset or 0
    if reset_ts > 0 and reset_ts < 1e12 then
        reset_ts = reset_ts * 1000 -- convert to ms if in seconds
    end

    -- Build snapshot
    local snapshot = {
        version = 1,
        timestamp = now_ms(),
        agent = "opencode",
        plan = plan,
        quota = {
            used = tokens_used,
            limit = tokens_limit,
            reset_ms = reset_ts,
            period = "day",
        },
        balance = nil, -- opencode doesn't have balance concept
        speaking = speaking,
        tokens_today = tokens_used,
        tokens_by_model = models,
        tokens_by_type = nil, -- opencode doesn't provide type breakdown
        limits = {},
    }

    -- Add limits array
    if tokens_limit > 0 then
        local pct = math.floor((tokens_used / tokens_limit) * 100)
        table.insert(snapshot.limits, {
            name = "Daily quota",
            used = tokens_used,
            limit = tokens_limit,
            reset_ms = reset_ts,
            percent = pct,
        })
    end

    return snapshot
end

return M