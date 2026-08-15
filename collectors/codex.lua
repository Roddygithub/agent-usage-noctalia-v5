-- Codex Collector for Agent Usage Monitor
-- Reads ~/.codex/sessions/ + optional app-server RPC
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local function now_ms()
    return os.time() * 1000
end

-- Current OpenAI models (2025-2026) - from OpenAI docs
local OPENAI_MODELS = {
    -- GPT-5.6 series (latest)
    "gpt-5.6-sol",
    "gpt-5.6-terra",
    "gpt-5.6-luna",
    -- GPT-5.5 series
    "gpt-5.5",
    "gpt-5.5-pro",
    -- GPT-5.4 series
    "gpt-5.4",
    "gpt-5.4-pro",
    "gpt-5.4-mini",
    "gpt-5.4-nano",
    -- GPT-5.3 series
    "gpt-5.3-codex",
    "gpt-5.3-codex-spark",
    -- GPT-5.2 series
    "gpt-5.2",
    "gpt-5.2-codex",
    -- GPT-5.1 series
    "gpt-5.1",
    "gpt-5.1-codex",
    "gpt-5.1-codex-max",
    "gpt-5.1-codex-mini",
    -- GPT-5
    "gpt-5",
    "gpt-5-codex",
    "gpt-5-nano",
    -- GPT-4o series
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4o-2024-11-20",
    "gpt-4o-2024-08-06",
    "gpt-4o-2024-05-13",
    -- GPT-4.5
    "gpt-4.5-preview",
    -- Specialized
    "gpt-5.6-cyber",
    "daybreak-red-latest",
    "daybreak-blue-latest",
    -- Realtime
    "gpt-realtime-2.1",
    "gpt-realtime-2.1-mini",
    "gpt-realtime-2",
    "gpt-realtime-translate",
    "gpt-realtime-1.5",
    -- Audio
    "gpt-4o-mini-tts",
    "gpt-transcribe",
    "gpt-live-transcribe",
    "gpt-realtime-whisper",
    "gpt-4o-transcribe",
    "gpt-4o-mini-transcribe",
    -- Image
    "gpt-image-2",
    -- Legacy
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo",
}

local M = {
    name = "codex",
    default_config = {
        enabled = true,
        config_dir = "~/.codex",
        use_rpc = true,
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
    if cfg.use_rpc ~= nil and type(cfg.use_rpc) ~= "boolean" then
        return false, "use_rpc must be boolean"
    end
    return true, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function expand_path(path)
    if path:sub(1, 1) == "~" then
        return os.getenv("HOME") .. path:sub(2)
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

local function list_session_files(dir)
    local files, err = noctalia.listDir(dir)
    if not files then return {}, err end
    local sessions = {}
    for _, file in ipairs(files) do
        if file:match("%.json$") then
            table.insert(sessions, dir .. "/" .. file)
        end
    end
    return sessions
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Session Parsing
-- ─────────────────────────────────────────────────────────────────────────────

local function parse_session_file(path)
    local data, err = read_json_file(path)
    if not data then return nil, err end

    -- Expected Codex session structure:
    -- {
    --   "session_id": "abc123",
    --   "model": "gpt-4o",
    --   "tokens": { "input": 1000, "output": 500, "cache": 100 },
    --   "timestamp": "2024-01-15T10:30:00.000Z",
    --   "active": false
    -- }

    local tokens = data.tokens or {}
    local model = data.model or "unknown"
    local active = data.active or false

    return {
        model = model,
        input = tokens.input or 0,
        output = tokens.output or 0,
        cache = tokens.cache or 0,
        total = (tokens.input or 0) + (tokens.output or 0) + (tokens.cache or 0),
        active = active,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC Call (Optional)
-- ─────────────────────────────────────────────────────────────────────────────

local function fetch_rpc_status(config)
    -- Codex app-server RPC for real-time status
    -- TODO: Implement actual RPC call
    return nil, "RPC not implemented yet"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Collection Function
-- ─────────────────────────────────────────────────────────────────────────────

function M.collect(config)
    config = config or M.default_config
    local config_dir = expand_path(config.config_dir or "~/.codex")

    -- Read all session files
    local session_files, err = list_session_files(config_dir)
    if not session_files or #session_files == 0 then
        return nil, "No Codex session files found in " .. config_dir
    end

    local models = {}
    local types = { input = 0, output = 0, cache = 0 }
    local daily = {}
    local speaking = false

    for _, file_path in ipairs(session_files) do
        local session, err = parse_session_file(file_path)
        if session then
            -- Aggregate by model
            models[session.model] = (models[session.model] or 0) + session.total
            types.input = types.input + (session.input or 0)
            types.output = types.output + (session.output or 0)
            types.cache = types.cache + (session.cache or 0)

            if session.active then
                speaking = true
            end

            -- Daily aggregation would need date parsing from filename/timestamp
            -- For now, skip daily aggregation from session files
        end
    end

    -- Calculate totals
    local total_tokens = 0
    for _, count in pairs(models) do
        total_tokens = total_tokens + count
    end

    -- Build snapshot
    local snapshot = {
        version = 1,
        timestamp = now_ms(),
        agent = "codex",
        plan = "Free", -- Codex doesn't expose plan in sessions
        quota = nil, -- Codex doesn't have quota limits in session files
        balance = nil,
        speaking = speaking,
        tokens_today = 0, -- Would need daily aggregation
        tokens_by_model = models,
        tokens_by_type = types,
        tokens_daily = {}, -- Would need daily aggregation
        limits = {},
    }

    -- Add limits if we can infer from usage patterns
    -- Codex doesn't have hard limits in session files

    return snapshot
end

return M