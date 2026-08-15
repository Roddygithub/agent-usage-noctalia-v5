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

    -- Parse enabled_agents (comma-separated string)
    local agents_str = noctalia.getConfig("enabled_agents") or "opencode,claude,codex,fireworks"
    for agent in string.gmatch(agents_str, "([^,]+)") do
        agent = string.gsub(agent, "^%s*(.-)%s*$", "%1") -- trim
        if agent ~= "" then
            table.insert(state.config.enabled_agents, agent)
        end
    end

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
-- Collector Loading & Validation
-- ─────────────────────────────────────────────────────────────────────────────

local function load_collectors()
    state.collectors = {}
    for _, agent_name in ipairs(state.config.enabled_agents) do
        local ok, collector = pcall(require, "collectors." .. agent_name)
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
        timestamp = math.floor(os.clock() * 1000) + os.time() * 1000, -- approximate ms
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
    for _ in pairs(merged_snapshot.agents) do agent_count = agent_count + 1 end
    log(string.format("Status published: primary=%s, agents=%d%s",
        primary or "none", agent_count, speaking))
end

local function publish_error_state(message)
    local error_snapshot = {
        version = 1,
        timestamp = math.floor(os.clock() * 1000) + os.time() * 1000,
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
        local ok, result = pcall(collector.collect, config)
        if not ok then
            log_warn("Collector '" .. agent_name .. "' threw error: " .. tostring(result))
            callback(nil, "Collector threw: " .. tostring(result))
            return
        end

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
end

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
                        -- Handle sync write if enabled
                        if state.config.sync_mode == "On" and state.config.sync_dir ~= "" then
                            write_sync_snapshot(merged)
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

local function check_speaking_agents(merged)
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

local function pulse_speaking(agent_name)
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Sync Writing
-- ─────────────────────────────────────────────────────────────────────────────

local function write_sync_snapshot(merged)
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
            timestamp = math.floor(os.clock() * 1000) + os.time() * 1000,
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
-- Lifecycle: init / shutdown / update
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    log("Service initializing...")
    load_config()
    load_collectors()

    -- Initial waiting state
    local initial_snapshot = {
        version = 1,
        timestamp = math.floor(os.clock() * 1000) + os.time() * 1000,
        agents = {},
        primary_agent = nil,
        speaking = false,
        message = "Initializing collectors...",
    }
    publish_status(initial_snapshot)

    -- Initial collect
    run_collectors()

    log("Service started")
end

function shutdown()
    log("Service shutting down...")
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
        timestamp = math.floor(os.clock() * 1000) + os.time() * 1000,
        agents = {},
        primary_agent = nil,
        speaking = false,
        message = "Service stopped",
    })
end

function update()
    -- Called by Noctalia at setUpdateInterval
    -- Polling is handled by run_collectors scheduled via setTimeout for retry logic
    -- This function exists to satisfy the service entry interface
end

function onIpc(payload)
    on_ipc(payload)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry Point
-- ─────────────────────────────────────────────────────────────────────────────

init()