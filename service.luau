-- Agent Usage Collector Service for Noctalia V5
-- Headless background service that polls AI agent usage collectors
-- Publishes normalized snapshots to noctalia.state for widget/panel/shortcut
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local LOG_PREFIX = "[agent-usage]"
local STATE_KEY_USAGE = "agent_usage"
local STATE_KEY_SPEAKING = "agent_usage_speaking"
local STATE_KEY_SYNC = "agent_usage_sync"
local MAX_RETRIES = 3
local BASE_RETRY_DELAY_MS = 1000
local CACHE_FILE = "state_cache.json"

local function now_ms()
    return os.time() * 1000
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal State
-- ─────────────────────────────────────────────────────────────────────────────

local state = {
    collectors = {},           -- { name = collector_module }
    collector_configs = {},    -- { name = config_table }
    config = {},               -- plugin settings
    cache = {},                -- { agent = last_snapshot }
    poll_timer = nil,
    consecutive_failures = {}, -- { agent = count }
    speaking_timers = {},      -- { agent = timer_id }
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Logging Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function log(msg)
    noctalia.log(LOG_PREFIX .. " " .. msg)
end

local function log_error(msg)
    log("ERROR: " .. msg)
    noctalia.notifyError("Agent Usage", msg)
end

local function log_warn(msg)
    log("WARN: " .. msg)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Persistence (pluginDataDir)
-- ─────────────────────────────────────────────────────────────────────────────

local function get_cache_path()
    local data_dir = noctalia.pluginDataDir()
    if not data_dir or data_dir == "" then
        return nil
    end
    return data_dir .. "/" .. CACHE_FILE
end

local function load_state_cache()
    local path = get_cache_path()
    if not path then return nil end

    local content, err = noctalia.readFile(path)
    if not content then
        log("No cache file found: " .. tostring(err))
        return nil
    end

    local ok, data = pcall(noctalia.json.decode, content)
    if not ok then
        log_warn("Failed to parse cache file: " .. tostring(data))
        return nil
    end

    -- Validate cache structure
    if not data.last_snapshot or not data.timestamp then
        log_warn("Invalid cache structure")
        return nil
    end

    -- Normalize restored snapshot fields
    if data.last_snapshot.agents == nil then data.last_snapshot.agents = {} end
    if data.last_snapshot.primary_agent == nil then data.last_snapshot.primary_agent = nil end
    if data.last_snapshot.speaking == nil then data.last_snapshot.speaking = false end

    -- Check cache age (max 24 hours)
    local age_ms = now_ms() - (data.timestamp or 0)
    if age_ms > 24 * 60 * 60 * 1000 then
        log("Cache expired (" .. math.floor(age_ms / 1000 / 60) .. " min old)")
        return nil
    end

    log("Loaded state cache (" .. math.floor(age_ms / 1000) .. "s old)")
    return data
end

local function save_state_cache(merged_snapshot)
    local path = get_cache_path()
    if not path then return end

    local cache_data = {
        version = 1,
        timestamp = now_ms(),
        last_snapshot = merged_snapshot,
        -- Could also save panel geometry, user prefs here
    }

    local ok, json_str = pcall(noctalia.json.encode, cache_data)
    if not ok then
        log_warn("Failed to encode cache: " .. tostring(json_str))
        return
    end

    local write_ok, err = noctalia.writeFile(path, json_str)
    if not write_ok then
        log_warn("Failed to write cache: " .. tostring(err))
    else
        log("State cache saved")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration Loading
-- ─────────────────────────────────────────────────────────────────────────────

local function load_config()
    state.config = {
        refresh_interval_sec = noctalia.getConfig("refresh_interval_sec") or 300,
        enabled_agents = {},
        sync_mode = noctalia.getConfig("sync_mode") or "Off",
        sync_dir = noctalia.getConfig("sync_dir") or "",
        sync_device_id = noctalia.getConfig("sync_device_id") or "",
        show_speaking_indicator = noctalia.getConfig("show_speaking_indicator") ~= false,
    }

    -- Parse enabled_agents (comma-separated string or string_list)
    local agents_config = noctalia.getConfig("enabled_agents")
    local agents_list = {}
    if type(agents_config) == "string" and agents_config ~= "" then
        -- Old format: comma-separated string
        for agent_raw in string.gmatch(agents_config, "([^,]+)") do
            local agent = string.gsub(agent_raw, "^%s*(.-)%s*$", "%1") -- trim
            if agent ~= "" then table.insert(agents_list, agent) end
        end
    elseif type(agents_config) == "table" and next(agents_config) ~= nil then
        -- New format: string_list (table of strings)
        for _, agent in ipairs(agents_config) do
            local trimmed = string.gsub(agent, "^%s*(.-)%s*$", "%1")
            if trimmed ~= "" then table.insert(agents_list, trimmed) end
        end
    else
        -- Fallback to defaults
        agents_list = {"opencode", "claude", "codex", "fireworks", "opencode-zen", "openrouter"}
    end
    state.config.enabled_agents = agents_list

    -- Load per-agent configs
    for _, agent in ipairs(state.config.enabled_agents) do
        local prefix = "collector_" .. agent .. "_"
        state.collector_configs[agent] = {}
        -- Collector-specific configs would be read here if defined in plugin.toml
        -- For now, use defaults from collector modules
    end

    log(string.format("Config loaded: refresh=%ds, agents=%s, sync=%s",
        state.config.refresh_interval_sec,
        table.concat(state.config.enabled_agents, ","),
        state.config.sync_mode
    ))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OpenCode Zen Detection (free models via opencode.ai)
-- ─────────────────────────────────────────────────────────────────────────────

local function detect_opencode_zen()
    -- Get HOME directory safely (os.getenv may not be available in sandbox)
    local home = os.getenv and os.getenv("HOME")
    if not home then
        -- Fallback: try to get from environment or use a default
        home = "/home/" .. (os.getenv and os.getenv("USER") or "roddy")
    end
    if not home or home == "" then
        return false, nil
    end
    local auth_path = home .. "/.local/share/opencode/auth.json"
    if not noctalia.readFile then
        return false, nil
    end
    local content, err = noctalia.readFile(auth_path)
    if not content then
        return false, nil
    end
    local ok, data = pcall(noctalia.json.decode, content)
    if not ok or not data then
        return false, nil
    end
    if data["opencode-zen"] then
        return true, data["opencode-zen"]
    end
    return false, nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Collector Loading & Validation
-- ─────────────────────────────────────────────────────────────────────────────

local function load_collectors()
    state.collectors = {}
    for _, agent_name in ipairs(state.config.enabled_agents) do
        -- opencode-zen is handled natively (no collector module)
        if agent_name == "opencode-zen" then
            log("opencode-zen handled natively, skipping collector load")
        else
            -- Require path must be relative (starting with ./) and end in .luau
            local require_path = "./collectors/" .. agent_name .. ".luau"
            local ok, collector = pcall(require, require_path)
            if not ok then
                log_warn("Failed to load collector '" .. agent_name .. "': " .. tostring(collector))
            elseif type(collector) ~= "table" then
                log_warn("Collector '" .. agent_name .. "' did not return a table")
            elseif not collector.name or not collector.collect then
                log_warn("Collector '" .. agent_name .. "' missing required fields (name, collect)")
            else
                -- Validate config if validator exists
                local cfg = state.collector_configs[agent_name] or collector.default_config or {}
                if collector.validate_config then
                    local valid, err = collector.validate_config(cfg)
                    if not valid then
                        log_warn("Collector '" .. agent_name .. "' config invalid: " .. tostring(err))
                    else
                        state.collectors[agent_name] = collector
                        log("Loaded collector: " .. agent_name)
                    end
                else
                    state.collectors[agent_name] = collector
                    log("Loaded collector: " .. agent_name)
                end
            end
        end
    end

    if next(state.collectors) == nil then
        log_warn("No collectors loaded successfully")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot Normalization & Publishing
-- ─────────────────────────────────────────────────────────────────────────────

local function merge_snapshots(snapshots)
    -- Merge multiple agent snapshots into a single combined snapshot
    -- Priority: speaking agent first, then by quota usage
    local merged = {
        version = 1,
        timestamp = now_ms(),
        agents = {},
        primary_agent = nil,
        speaking = false,
    }

    local speaking_agent = nil
    local max_quota_pct = -1

    for agent_name, snap in pairs(snapshots) do
        if snap then
            merged.agents[agent_name] = snap
            -- Track speaking agent
            if snap.speaking then
                speaking_agent = agent_name
                merged.speaking = true
            end
            -- Track highest quota usage for primary display
            if snap.quota and snap.quota.limit and snap.quota.limit > 0 then
                local pct = (snap.quota.used / snap.quota.limit) * 100
                if pct > max_quota_pct then
                    max_quota_pct = pct
                    if not speaking_agent then
                        merged.primary_agent = agent_name
                    end
                end
            elseif not merged.primary_agent then
                merged.primary_agent = agent_name
            end
        end
    end

    -- Set primary agent for widget display
    if speaking_agent then
        merged.primary_agent = speaking_agent
    elseif not merged.primary_agent then
        -- Pick first available
        for k, _ in pairs(merged.agents) do
            merged.primary_agent = k
            break
        end
    end

    return merged
end

local function publish_status(merged_snapshot)
    -- Publish main agent usage state
    noctalia.state.set(STATE_KEY_USAGE, merged_snapshot)

    -- Publish speaking state separately for pulse animation
    noctalia.state.set(STATE_KEY_SPEAKING, merged_snapshot.speaking)

    -- Log summary
    local primary = merged_snapshot.primary_agent
    local speaking = merged_snapshot.speaking and " (speaking)" or ""
    local agent_count = 0
    local agents = merged_snapshot.agents or {}
    for _ in pairs(agents) do agent_count = agent_count + 1 end
    log(string.format("Status published: primary=%s, agents=%d%s",
        primary or "none", agent_count, speaking))
end

local function publish_error_state(message)
    local error_snapshot = {
        version = 1,
        timestamp = now_ms(),
        agents = {},
        primary_agent = nil,
        speaking = false,
        error = message,
    }
    publish_status(error_snapshot)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Collector Execution with Retry Logic
-- ─────────────────────────────────────────────────────────────────────────────

local function execute_collector(agent_name, collector, config)
    return function(callback)
        local function handle_result(result)
            if result then
                -- Validate snapshot has required fields
                if result.version and result.timestamp and result.agent then
                    -- Ensure agent field matches
                    result.agent = agent_name
                    callback(result, nil)
                else
                    callback(nil, "Invalid snapshot: missing required fields")
                end
            else
                callback(nil, result or "Collector returned nil")
            end
        end

        -- Async collectors (e.g. network-backed) use collector.collect_async(config, callback)
        if collector.collect_async then
            local ok, err = pcall(collector.collect_async, config, function(snapshot, collect_err)
                if snapshot then
                    handle_result(snapshot)
                else
                    callback(nil, collect_err or "Collector returned nil")
                end
            end)
            if not ok then
                log_warn("Collector '" .. agent_name .. "' threw error: " .. tostring(err))
                callback(nil, "Collector threw: " .. tostring(err))
            end
            return
        end

        local ok, result = pcall(collector.collect, config)
        if not ok then
            log_warn("Collector '" .. agent_name .. "' threw error: " .. tostring(result))
            callback(nil, "Collector threw: " .. tostring(result))
            return
        end

        handle_result(result)
    end
end

-- Forward declarations for functions defined below but called from run_collectors
local read_sync_snapshots, merge_sync_snapshots, publish_sync_status, write_sync_snapshot
local pulse_speaking, check_speaking_agents

local function run_collectors()
    local pending = 0
    local results = {}
    local errors = {}

    for agent_name, collector in pairs(state.collectors) do
        local config = state.collector_configs[agent_name] or collector.default_config or {}
        pending = pending + 1

        execute_collector(agent_name, collector, state.collector_configs[agent_name] or {})(
            function(snapshot, err)
                pending = pending - 1
                if snapshot then
                    results[agent_name] = snapshot
                    state.cache[agent_name] = snapshot
                    state.consecutive_failures[agent_name] = 0
                else
                    errors[agent_name] = err
                    state.consecutive_failures[agent_name] = (state.consecutive_failures[agent_name] or 0) + 1
                    log_warn("Collector '" .. agent_name .. "' failed (" ..
                        state.consecutive_failures[agent_name] .. "/" .. MAX_RETRIES .. "): " .. tostring(err))
                end

                if pending == 0 then
                    -- All collectors done, merge and publish
                    local merged = merge_snapshots(results)
                    if next(merged.agents) == nil and next(errors) ~= nil then
                        -- All failed
                        local err_msgs = {}
                        for a, e in pairs(errors) do table.insert(err_msgs, a .. ": " .. tostring(e)) end
                        publish_error_state("All collectors failed: " .. table.concat(err_msgs, "; "))
                    else
                        publish_status(merged)
                        -- Save state cache for persistence
                        save_state_cache({ last_snapshot = merged, sync = noctalia.state.get(STATE_KEY_SYNC) })
                        -- Handle sync write if enabled
                        if state.config.sync_mode == "On" and state.config.sync_dir ~= "" then
                            write_sync_snapshot(merged)
                        end
                        -- Handle sync read/merge if enabled
                        if state.config.sync_mode == "On" and state.config.sync_dir ~= "" then
                            local sync_snapshots, err = read_sync_snapshots()
                            if sync_snapshots and #sync_snapshots > 0 then
                                local merged_sync = merge_sync_snapshots(sync_snapshots)
                                if merged_sync then
                                    publish_sync_status(merged_sync)
                                end
                            end
                        end
                    end

                    -- Check for speaking agents to trigger pulse
                    check_speaking_agents(merged)
                end
            end
        )
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Speaking Pulse Management
-- ─────────────────────────────────────────────────────────────────────────────

function pulse_speaking(agent_name)
    if not state.speaking_timers[agent_name] then return end

    local pulse_on = true
    local function toggle()
        if not state.speaking_timers[agent_name] then return end
        pulse_on = not pulse_on
        -- The widget will read STATE_KEY_SPEAKING and animate accordingly
        noctalia.state.set(STATE_KEY_SPEAKING, pulse_on)
        noctalia.setTimeout(500, toggle)
    end
    toggle()
end

function check_speaking_agents(merged)
    if not state.config.show_speaking_indicator then return end

    local speaking_agent = nil
    for agent_name, snap in pairs(merged.agents) do
        if snap.speaking then
            speaking_agent = agent_name
            break
        end
    end

    if speaking_agent then
        -- Start/continue pulse timer
        if not state.speaking_timers[speaking_agent] then
            state.speaking_timers[speaking_agent] = true
            pulse_speaking(speaking_agent)
        end
    else
        -- Stop all pulse timers
        for agent, _ in pairs(state.speaking_timers) do
            state.speaking_timers[agent] = nil
        end
        noctalia.state.set(STATE_KEY_SPEAKING, false)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sync Read & Merge
-- ─────────────────────────────────────────────────────────────────────────────

function read_sync_snapshots()
    if state.config.sync_dir == "" then
        return {}, "sync_dir not configured"
    end

    local files, err = noctalia.listDir(state.config.sync_dir)
    if not files then
        return {}, "Failed to list sync_dir: " .. tostring(err)
    end

    local snapshots = {}
    for _, file in ipairs(files) do
        if file:match("%.json$") then
            local filepath = state.config.sync_dir .. "/" .. file
            local content, err = noctalia.readFile(filepath)
            if content then
                local ok, data = pcall(noctalia.json.decode, content)
                if ok and data and data.snapshot then
                    -- Extract device_id from filename (without .json)
                    local device_id = file:gsub("%.json$", "")
                    data.snapshot.device_id = device_id
                    data.snapshot.sync_timestamp = data.timestamp
                    table.insert(snapshots, data.snapshot)
                end
            end
        end
    end

    return snapshots, nil
end

function merge_sync_snapshots(snapshots)
    if #snapshots == 0 then
        return nil
    end

    -- Start with the most recent snapshot as base
    table.sort(snapshots, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    local merged = {
        version = 1,
        timestamp = now_ms(),
        agents = {},
        primary_agent = nil,
        speaking = false,
        sync = {
            mode = state.config.sync_mode,
            dir = state.config.sync_dir,
            devices = {},
            last_sync = 0,
            merged_from = #snapshots,
        }
    }

    local latest_timestamp = 0

    for _, snap in ipairs(snapshots) do
        -- Track devices
        if snap.device_id then
            table.insert(merged.sync.devices, {
                id = snap.device_id,
                last_seen = snap.sync_timestamp or snap.timestamp,
                primary_agent = snap.primary_agent,
            })
            if (snap.sync_timestamp or snap.timestamp) > latest_timestamp then
                latest_timestamp = snap.sync_timestamp or snap.timestamp
            end
        end

        -- Merge agents
        for agent_name, agent_snap in pairs(snap.agents or {}) do
            if not merged.agents[agent_name] then
                merged.agents[agent_name] = agent_snap
            else
                -- Merge logic per agent
                local existing = merged.agents[agent_name]

                -- Tokens by day: union by date (not sum)
                if agent_snap.tokens_daily and existing.tokens_daily then
                    local day_map = {}
                    for _, day in ipairs(existing.tokens_daily) do
                        day_map[day.date] = day
                    end
                    for _, day in ipairs(agent_snap.tokens_daily) do
                        if not day_map[day.date] then
                            table.insert(existing.tokens_daily, day)
                        elseif day.tokens > (day_map[day.date].tokens or 0) then
                            day_map[day.date].tokens = day.tokens
                        end
                    end
                elseif agent_snap.tokens_daily and not existing.tokens_daily then
                    existing.tokens_daily = agent_snap.tokens_daily
                end

                -- Tokens by model: sum
                if agent_snap.tokens_by_model and existing.tokens_by_model then
                    for model, tokens in pairs(agent_snap.tokens_by_model) do
                        existing.tokens_by_model[model] = (existing.tokens_by_model[model] or 0) + tokens
                    end
                elseif agent_snap.tokens_by_model and not existing.tokens_by_model then
                    existing.tokens_by_model = agent_snap.tokens_by_model
                end

                -- Tokens by type: sum
                if agent_snap.tokens_by_type and existing.tokens_by_type then
                    for typ, tokens in pairs(agent_snap.tokens_by_type) do
                        existing.tokens_by_type[typ] = (existing.tokens_by_type[typ] or 0) + tokens
                    end
                elseif agent_snap.tokens_by_type and not existing.tokens_by_type then
                    existing.tokens_by_type = agent_snap.tokens_by_type
                end

                -- Quota/limits: take max (per account, not sum)
                if agent_snap.quota and existing.quota then
                    if (agent_snap.quota.limit or 0) > (existing.quota.limit or 0) then
                        existing.quota = agent_snap.quota
                    end
                elseif agent_snap.quota and not existing.quota then
                    existing.quota = agent_snap.quota
                end

                -- Limits: per account max, not sum
                if agent_snap.limits and existing.limits then
                    local limit_map = {}
                    for _, l in ipairs(existing.limits) do
                        limit_map[l.name] = l
                    end
                    for _, l in ipairs(agent_snap.limits) do
                        if not limit_map[l.name] or (l.limit or 0) > (limit_map[l.name].limit or 0) then
                            limit_map[l.name] = l
                        end
                    end
                    -- Rebuild array
                    existing.limits = {}
                    for _, l in pairs(limit_map) do
                        table.insert(existing.limits, l)
                    end
                elseif agent_snap.limits and not existing.limits then
                    existing.limits = agent_snap.limits
                end

                -- Balance: if different accounts, don't merge (keep both separately)
                -- For now, keep the one with higher funded amount if both exist
                if agent_snap.balance and existing.balance then
                    if (agent_snap.balance.credits or 0) > (existing.balance.credits or 0) then
                        existing.balance = agent_snap.balance
                    end
                elseif agent_snap.balance and not existing.balance then
                    existing.balance = agent_snap.balance
                end

                -- Speaking: true if any device is speaking
                existing.speaking = existing.speaking or agent_snap.speaking
            end
        end
    end

    -- Determine primary agent from merged
    for agent, snap in pairs(merged.agents) do
        if snap.speaking then
            merged.primary_agent = agent
            merged.speaking = true
            break
        end
    end
    if not merged.primary_agent then
        for agent, _ in pairs(merged.agents) do
            merged.primary_agent = agent
            break
        end
    end

    merged.sync.last_sync = latest_timestamp

    return merged
end

function publish_sync_status(merged_sync)
    if merged_sync then
        noctalia.state.set(STATE_KEY_SYNC, merged_sync)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sync Writing
-- ─────────────────────────────────────────────────────────────────────────────

function write_sync_snapshot(merged)
    if state.config.sync_dir == "" then return end

    local sync_data = {
        version = 1,
        timestamp = merged.timestamp,
        device_id = state.config.sync_device_id ~= "" and state.config.sync_device_id or "unknown",
        snapshot = merged,
    }

    local filename = (state.config.sync_device_id ~= "" and state.config.sync_device_id or "unknown") .. ".json"
    local filepath = state.config.sync_dir .. "/" .. filename

    local ok, json_str = pcall(noctalia.json.encode, sync_data)
    if not ok then
        log_warn("Failed to encode sync snapshot: " .. tostring(json_str))
        return
    end

    local write_ok, err = noctalia.writeFile(filepath, json_str)
    if not write_ok then
        log_warn("Failed to write sync snapshot: " .. tostring(err))
    else
        log("Sync snapshot written: " .. filepath)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- IPC Command Handling
-- ─────────────────────────────────────────────────────────────────────────────

local function on_ipc(payload)
    if not payload or not payload.cmd then
        log_warn("Received IPC with no command")
        return
    end

    log("IPC received: " .. payload.cmd)

    if payload.cmd == "refresh" then
        log("Manual refresh requested")
        run_collectors()
    elseif payload.cmd == "toggle_sync" then
        local new_mode = (state.config.sync_mode == "On") and "Off" or "On"
        state.config.sync_mode = new_mode
        log("Sync mode toggled: " .. new_mode)
        -- Note: Config persistence is handled by Noctalia settings system
        -- The change will be reflected in getConfig() on next poll
        run_collectors() -- Immediate poll with new setting
    elseif payload.cmd == "force_sync" then
        -- Force immediate sync write
        local merged = {
            version = 1,
            timestamp = now_ms(),
            agents = state.cache,
            primary_agent = nil,
            speaking = false,
        }
        -- Determine primary from cache
        for agent, snap in pairs(state.cache) do
            if snap.speaking then
                merged.primary_agent = agent
                break
            end
        end
        if not merged.primary_agent then
            for k, _ in pairs(merged.agents) do
                merged.primary_agent = k
                break
            end
        end
        write_sync_snapshot(merged)
        log("Force sync written")
    else
        log_warn("Unknown IPC command: " .. payload.cmd)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OpenCode Zen Status (free models, no API tracking available)
-- ─────────────────────────────────────────────────────────────────────────────

local function add_opencode_zen_status()
    local zen_snapshot = {
        version = 1,
        timestamp = now_ms(),
        agent = "opencode-zen",
        plan = "Free (OpenCode Zen)",
        quota = nil,
        balance = nil,
        speaking = false,
        tokens_today = 0,
        tokens_by_model = {
            ["DeepSeek V4 Flash Free"] = 0,
            ["MiMo-V2.5 Free"] = 0,
            ["Hy3 Free"] = 0,
            ["Laguna S 2.1 Free"] = 0,
            ["Nemotron 3 Ultra Free"] = 0,
            ["Nemotron 3.5 Lightning Free"] = 0,
        },
        tokens_by_type = nil,
        limits = {},
        note = "Free models via opencode.ai/zen — no usage tracking available. Check dashboard at opencode.ai",
    }
    state.cache["opencode-zen"] = zen_snapshot
    
    -- Re-merge and publish
    local merged = merge_snapshots(state.cache)
    publish_status(merged)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle: init / shutdown / update
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    log("Service initializing...")
    load_config()
    noctalia.setUpdateInterval(state.config.refresh_interval_sec * 1000)
    load_collectors()

    -- Detect OpenCode Zen (free models)
    local zen_enabled, zen_config = detect_opencode_zen()
    if zen_enabled then
        log("OpenCode Zen detected: free models active")
    end

    -- Load cached state for immediate display
    local cached = load_state_cache()
    if cached and cached.last_snapshot then
        log("Restoring cached state")
        publish_status(cached.last_snapshot)
        -- Also restore sync status if available
        if cached.sync then
            publish_sync_status(cached.sync)
        end
    else
        -- Initial waiting state
        local initial_snapshot = {
            version = 1,
            timestamp = now_ms(),
            agents = {},
            primary_agent = nil,
            speaking = false,
            message = "Initializing collectors...",
        }
        publish_status(initial_snapshot)
    end

    -- Initial collect
    run_collectors()

    -- Initial sync read if enabled
    if state.config.sync_mode == "On" and state.config.sync_dir ~= "" then
        local sync_snapshots, err = read_sync_snapshots()
        if sync_snapshots and #sync_snapshots > 0 then
            local merged_sync = merge_sync_snapshots(sync_snapshots)
            if merged_sync then
                publish_sync_status(merged_sync)
            end
        end
    end

    -- Add OpenCode Zen status after initial collect
    if zen_enabled then
        add_opencode_zen_status()
    end

    log("Service started")
end

function shutdown()
    log("Service shutting down...")

    -- Save state cache for next startup
    local current_snapshot = noctalia.state.get(STATE_KEY_USAGE)
    local current_sync = noctalia.state.get(STATE_KEY_SYNC)
    if current_snapshot then
        local cache_data = {
            last_snapshot = current_snapshot,
            sync = current_sync,
        }
        save_state_cache(cache_data)
    end

    if state.poll_timer then
        noctalia.clearTimeout(state.poll_timer)
        state.poll_timer = nil
    end
    -- Clear speaking timers
    for agent, _ in pairs(state.speaking_timers) do
        state.speaking_timers[agent] = nil
    end
    publish_status({
        version = 1,
        timestamp = now_ms(),
        agents = {},
        primary_agent = nil,
        speaking = false,
        message = "Service stopped",
    })
end

function update()
    -- Called by Noctalia at setUpdateInterval
    noctalia.setUpdateInterval(state.config.refresh_interval_sec * 1000)
    run_collectors()
end

function onIpc(payload)
    on_ipc(payload)
end

function onConfigChanged()
    load_config()
    noctalia.setUpdateInterval(state.config.refresh_interval_sec * 1000)
    run_collectors()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry Point
-- ─────────────────────────────────────────────────────────────────────────────

init()