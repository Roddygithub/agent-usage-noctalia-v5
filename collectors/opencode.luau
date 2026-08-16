-- opencode Collector for Agent Usage Monitor
-- Reads real quota from the OpenAI Codex usage API (wham/usage) using the
-- OAuth token stored in ~/.local/share/opencode/auth.json.
-- Falls back to the local ~/.config/opencode/usage.json on auth/network failure.
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

local M = {
    name = "opencode",
    default_config = {
        enabled = true,
        config_path = "~/.config/opencode/usage.json",
        auth_path = "~/.local/share/opencode/auth.json",
        usage_api = "https://chatgpt.com/backend-api/wham/usage",
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Config Validation
-- ─────────────────────────────────────────────────────────────────────────────

function M.validate_config(cfg)
    if not cfg then return true, nil end
    for _, k in ipairs({ "config_path", "auth_path", "usage_api" }) do
        if cfg[k] and type(cfg[k]) ~= "string" then
            return false, k .. " must be string"
        end
    end
    return true, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Local fallback: parse ~/.config/opencode/usage.json
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

    -- Normalize tokens_by_model: values may be plain numbers or objects {tokens, ...}
    local normalized_models = {}
    for model, v in pairs(models) do
        if type(v) == "table" then
            normalized_models[model] = v.tokens or v.count or 0
        else
            normalized_models[model] = v
        end
    end

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
        tokens_by_model = normalized_models,
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Auth + network helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function read_auth_json()
    local auth_path = expand_path(M.default_config.auth_path)
    local content, err = noctalia.readFile(auth_path)
    if not content then return nil, err end
    local ok, data = pcall(noctalia.json.decode, content)
    if not ok then return nil, "JSON parse error: " .. tostring(data) end
    return data, nil
end

local function fetch_openai_usage(token, api_url, callback)
    local cmd = "curl -s -w \"\\nHTTP_CODE:%{http_code}\" -H \"Authorization: Bearer " .. token
        .. "\" -H \"Content-Type: application/json\" \"" .. api_url .. "\""
    noctalia.runAsync(cmd, function(result)
        if not result then
            callback(nil, "runAsync returned nil")
            return
        end
        local stdout = result.stdout or ""
        local http_code = stdout:match("HTTP_CODE:(%d+)")
        local body = stdout:match("(.-)\n?HTTP_CODE:%d+$")
        if not http_code then
            callback(nil, "curl produced no HTTP_CODE (network error): " .. tostring(stdout:sub(1, 120) or ""))
            return
        end
        local ok, data = pcall(noctalia.json.decode, body)
        if not ok then callback(nil, "JSON parse error: " .. tostring(data)) return end
        if http_code ~= "200" then
            callback(nil, "HTTP " .. tostring(http_code) .. " from usage API")
            return
        end
        callback(data, nil)
    end)
end

-- Map the API window size to a human period label
local function window_period(seconds)
    if seconds == 18000 then return "5h" end
    if seconds == 86400 then return "day" end
    if seconds == 604800 then return "week" end
    if seconds == 2592000 then return "month" end
    return "window"
end

local function capitalize(s)
    if not s or s == "" then return s or "" end
    return s:sub(1, 1):upper() .. s:sub(2)
end

-- Build a snapshot from the wham/usage API response
local function build_quota_snapshot(data)
    local plan_type = data.plan_type or "free"
    local rate_limit = data.rate_limit or {}
    local primary = rate_limit.primary_window or {}
    local used_pct = math.floor(primary.used_percent or 0)

    local reset_at = primary.reset_at or 0
    local reset_ms = reset_at > 0 and (reset_at * 1000) or 0

    local period = window_period(primary.limit_window_seconds or 604800)

    local credits = data.credits or {}
    local balance = nil
    if credits.has_credits then
        balance = {
            credits = tonumber(credits.balance) or 0,
            currency = "USD",
            estimated = false,
        }
    end

    return {
        version = 1,
        timestamp = now_ms(),
        agent = "opencode",
        plan = capitalize(plan_type),
        quota = {
            used = used_pct,
            limit = 100,
            reset_ms = reset_ms,
            period = period,
            percent = used_pct,
        },
        balance = balance,
        speaking = false,
        tokens_today = 0, -- wham/usage does not report absolute token counts
        tokens_by_model = {},
        tokens_by_type = nil,
        limits = {
            {
                name = "Codex quota (" .. period .. ")",
                used = used_pct,
                limit = 100,
                reset_ms = reset_ms,
                percent = used_pct,
            },
        },
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Async collection (network-backed, primary path)
-- ─────────────────────────────────────────────────────────────────────────────

function M.collect_async(config, callback)
    config = config or M.default_config
    local api_url = config.usage_api or M.default_config.usage_api

    local function fallback(reason)
        local snap, err = M.collect(config)
        if snap then
            snap.note = "Real-time quota unavailable (" .. tostring(reason) .. "); using local data"
            callback(snap, reason)
        else
            callback(nil, "usage API unavailable (" .. tostring(reason) .. "): " .. tostring(err))
        end
    end

    local auth_data, err = read_auth_json()
    if not auth_data then
        fallback("auth.json unreadable: " .. tostring(err))
        return
    end

    local openai = auth_data.openai or {}
    local token = openai.access
    if not token or token == "" then
        fallback("no OpenAI OAuth token in auth.json")
        return
    end

    fetch_openai_usage(token, api_url, function(data, fetch_err)
        if not data then
            fallback("wham/usage failed: " .. tostring(fetch_err))
            return
        end
        callback(build_quota_snapshot(data), nil)
    end)
end

return M