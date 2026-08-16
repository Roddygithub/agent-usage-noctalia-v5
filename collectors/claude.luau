-- Claude Collector for Agent Usage Monitor
-- Reads ~/.claude/stats-cache.json, history.jsonl, and optionally uses OAuth API
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

-- Current Claude models (2025-2026) - from Anthropic docs
local CLAUDE_MODELS = {
    -- Current flagship models
    "claude-fable-5",
    "claude-opus-5",
    "claude-sonnet-5",
    "claude-haiku-4-5",
    -- Legacy models (still available)
    "claude-opus-4-8",
    "claude-opus-4-7",
    "claude-opus-4-6",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5",
    "claude-opus-4-5",
    "claude-3-5-sonnet-20241022",
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
    "claude-3-sonnet-20240229",
    "claude-3-haiku-20240307",
}

local M = {
    name = "claude",
    default_config = {
        enabled = true,
        config_dir = "~/.claude",
        use_oauth = true,
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Config Validation
-- ─────────────────────────────────────────────────────────────────────────────

function M.validate_config(cfg)
    if not cfg then return true, nil end
    if cfg.config_dir and type(cfg.config_dir) ~= "string" then
        return false, "config_dir must be string"
    end
    if cfg.use_oauth ~= nil and type(cfg.use_oauth) ~= "boolean" then
        return false, "use_oauth must be boolean"
    end
    return true, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function expand_path(path)
    if path:sub(1, 1) == "~" then
        return home_dir() .. path:sub(2)
    end
    return path
end

local function read_json_file(path)
    local content, err = noctalia.readFile(path)
    if not content then return nil, err end
    local ok, data = pcall(noctalia.json.decode, content)
    if not ok then return nil, "JSON parse error: " .. tostring(data) end
    return data, nil
end

local function parse_iso8601_to_ms(iso_str)
    -- Parse ISO 8601 timestamp to milliseconds
    -- Format: "2024-01-15T10:30:00.000Z"
    if not iso_str then return 0 end
    local year, month, day, hour, min, sec = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not year then return 0 end
    local t = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour), min = tonumber(min), sec = tonumber(sec) })
    return t * 1000
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Local Cache Reading (stats-cache.json + history.jsonl)
-- ─────────────────────────────────────────────────────────────────────────────

local function read_local_cache(config)
    local config_dir = expand_path(config.config_dir or "~/.claude")
    local cache_path = config_dir .. "/stats-cache.json"
    local history_path = config_dir .. "/history.jsonl"

    -- Read stats-cache.json (primary source for quota/balance)
    local cache_data, err = read_json_file(cache_path)
    if not cache_data then
        return nil, "Failed to read stats-cache.json: " .. tostring(err)
    end

    -- Expected stats-cache.json structure:
    -- {
    --   "plan": "Pro",
    --   "quota": { "used": 150000, "limit": 1000000, "reset": "2024-01-15T10:30:00.000Z" },
    --   "balance": { "credits": 50.00, "currency": "USD" },
    --   "usage_by_model": { "claude-3-opus": 50000, "claude-3-sonnet": 100000 },
    --   "usage_by_type": { "input": 80000, "output": 70000, "cache": 10000 },
    --   "daily_usage": [ { "date": "2024-01-15", "tokens": 45000 }, ... ],
    --   "speaking": false
    -- }

    local quota = cache_data.quota or {}
    local balance = cache_data.balance or {}
    local models = cache_data.usage_by_model or {}
    local types = cache_data.usage_by_type or {}
    local daily = cache_data.daily_usage or {}
    local speaking = cache_data.speaking or false

    -- Parse reset timestamp
    local reset_ms = 0
    if quota.reset then
        reset_ms = parse_iso8601_to_ms(quota.reset)
    end

    -- Build daily usage array for 7-day chart
    local daily_usage = {}
    for _, day in ipairs(daily) do
        table.insert(daily_usage, {
            date = day.date,
            tokens = day.tokens or 0,
            today = (day.date == os.date("%Y-%m-%d")),
        })
    end

    -- Calculate tokens today
    local tokens_today = 0
    local today_str = os.date("%Y-%m-%d")
    for _, day in ipairs(daily) do
        if day.date == today_str then
            tokens_today = day.tokens or 0
            break
        end
    end

    -- Build limits array
    local limits = {}
    if cache_data.quota then
        local q = cache_data.quota
        local used = q.used or 0
        local limit = q.limit or 0
        local pct = limit > 0 and math.floor((used / limit) * 100) or 0
        local reset_ms = q.reset and parse_iso8601_to_ms(q.reset) or 0
        table.insert(limits, {
            name = "Daily quota",
            used = used,
            limit = limit,
            reset_ms = reset_ms,
            percent = pct,
        })
    end

    -- Add weekly limit if available
    if cache_data.weekly_quota then
        local q = cache_data.weekly_quota
        local used = q.used or 0
        local limit = q.limit or 0
        local pct = limit > 0 and math.floor((used / limit) * 100) or 0
        local reset_ms = q.reset and parse_iso8601_to_ms(q.reset) or 0
        table.insert(limits, {
            name = "Weekly quota",
            used = used,
            limit = limit,
            reset_ms = reset_ms,
            percent = pct,
        })
    end

    -- Build balance object
    local balance_obj = nil
    if balance.credits then
        balance_obj = {
            credits = balance.credits or 0,
            currency = balance.currency or "USD",
            estimated = false,
        }
    end

    return {
        version = 1,
        timestamp = now_ms(),
        agent = "claude",
        plan = cache_data.plan or "Pro",
        quota = {
            used = quota.used or 0,
            limit = quota.limit or 0,
            reset_ms = reset_ms,
            period = "day",
        },
        balance = balance_obj,
        speaking = false, -- Will be set by API if available
        tokens_today = tokens_today,
        tokens_by_model = models,
        tokens_by_type = types,
        tokens_daily = daily_usage,
        limits = limits,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OAuth API Call (Optional - for real-time speaking status)
-- ─────────────────────────────────────────────────────────────────────────────

local function fetch_oauth_status(config)
    -- This would call Anthropic's OAuth API for real-time status
    -- For now, return nil to use local cache only
    -- TODO: Implement OAuth token refresh and API call
    return nil, "OAuth not implemented yet"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Collection Function
-- ─────────────────────────────────────────────────────────────────────────────

function M.collect(config)
    config = config or M.default_config

    -- Read local cache (always available)
    local snapshot, err = read_local_cache(config)
    if not snapshot then
        return nil, "Failed to read local cache: " .. tostring(err)
    end

    -- Optionally enhance with OAuth API (speaking status, real-time quota)
    if config.use_oauth then
        local oauth_data, err = fetch_oauth_status(config)
        if oauth_data then
            -- Merge OAuth data (speaking status, real-time quota)
            snapshot.speaking = oauth_data.speaking or false
            if oauth_data.quota then
                snapshot.quota = oauth_data.quota
            end
        else
            if noctalia and noctalia.log then
                noctalia.log("[agent-usage] WARN: Claude OAuth unavailable: " .. tostring(err) .. ", using local cache")
            end
        end
    end

    return snapshot
end

return M