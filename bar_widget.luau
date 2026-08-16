-- Agent Usage Bar Widget for Noctalia V5
-- Compact status indicator showing agent quota and speaking status
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local STATE_KEY_USAGE = "agent_usage"
local STATE_KEY_SPEAKING = "agent_usage_speaking"

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration
-- ─────────────────────────────────────────────────────────────────────────────

local config = {}

local function load_config()
    config = {
        glyph_opencode = noctalia.getConfig("glyph_opencode") or "terminal",
        glyph_claude = noctalia.getConfig("glyph_claude") or "bot",
        glyph_codex = noctalia.getConfig("glyph_codex") or "database",
        glyph_fireworks = noctalia.getConfig("glyph_fireworks") or "flame",
        glyph_openrouter = noctalia.getConfig("glyph_openrouter") or "route",
        glyph_opencode_zen = noctalia.getConfig("glyph_opencode_zen") or "sparkles",
        hide_when_idle = noctalia.getConfig("hide_when_idle") or false,
    }
end

-- Panel ID based on panel_placement setting (like Phone Connect)
local function panelId()
    local mode = noctalia.getConfig("panel_placement")
    if mode == "floating" then
        return "roddygithub/agent-usage:detail_floating"
    elseif mode == "widget" then
        return "roddygithub/agent-usage:detail_widget"
    end
    return "roddygithub/agent-usage:detail_attached"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Agent Glyph & Color Mapping
-- ─────────────────────────────────────────────────────────────────────────────

local AGENT_GLYPHS = {
    opencode = "glyph_opencode",
    claude = "glyph_claude",
    codex = "glyph_codex",
    fireworks = "glyph_fireworks",
    ["opencode-zen"] = "glyph_opencode_zen",
    openrouter = "glyph_openrouter",
}

local AGENT_COLORS = {
    opencode = "blue",
    claude = "purple",
    codex = "green",
    fireworks = "orange",
    ["opencode-zen"] = "green",
    openrouter = "cyan",
}

local AGENT_LABELS = {
    opencode = "opencode",
    claude = "Claude",
    codex = "Codex",
    fireworks = "Fireworks",
    ["opencode-zen"] = "OpenCode Zen",
    openrouter = "OpenRouter",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function format_quota(quota)
    if not quota or not quota.limit or quota.limit == 0 then
        return quota.used .. " / ∞"
    end
    local pct = math.floor((quota.used / quota.limit) * 100)
    return string.format("%d%%", pct)
end

local function format_balance(balance)
    if not balance then return "—" end
    local est = balance.estimated and " (est.)" or ""
    return string.format("$%.2f%s", balance.credits, est)
end

local function format_time_ms(ms)
    if not ms or ms == 0 then return "—" end
    local diff = math.floor(ms / 1000) - os.time()
    if diff <= 0 then return "now" end
    if diff < 60 then return diff .. "s" end
    if diff < 3600 then return math.floor(diff / 60) .. "m" end
    if diff < 86400 then return math.floor(diff / 3600) .. "h" end
    return math.floor(diff / 86400) .. "d"
end

local function get_agent_color(agent, speaking)
    if speaking then return "pulse" end
    return AGENT_COLORS[agent] or "gray"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────────────────────

local pulse_state = false
local pulse_timer = nil

local function render(merged)
    local primary = merged.primary_agent
    local speaking = merged.speaking

    -- Visibility
    local visible = true
    if config.hide_when_idle then
        local has_active = false
        for agent, snap in pairs(merged.agents or {}) do
            if snap.speaking or (snap.quota and snap.quota.limit and snap.quota.limit > 0 and snap.quota.used > 0) then
                has_active = true
                break
            end
        end
        visible = has_active
    end
    barWidget.setVisible(visible)

    if not visible then return end

    -- Determine primary agent for display
    local display_agent = primary
    local display_snap = primary and merged.agents[primary]

    if not display_snap then
        -- No primary agent, show first available
        for agent, snap in pairs(merged.agents or {}) do
            display_agent = agent
            display_snap = snap
            break
        end
    end

    if not display_snap then
        -- No agents loaded
        local msg = merged.message or "No agents"
        barWidget.setGlyph(config.glyph_opencode)
        barWidget.setText(msg)
        barWidget.setVisible(not config.hide_when_idle)
        return
    end

    -- Glyph
    local glyph_key = AGENT_GLYPHS[display_agent] or "glyph_opencode"
    local glyph = config[glyph_key] or "code"
    barWidget.setGlyph(glyph)

    -- Text: Agent label + quota
    local quota_text = display_snap.quota and format_quota(display_snap.quota) or "—"
    local label = AGENT_LABELS[display_agent] or display_agent
    local text = label .. " " .. quota_text

    -- Speaking indicator
    if display_snap.speaking and state.config.show_speaking_indicator then
        text = text .. " ●"
    end

    barWidget.setText(text)

    -- Color based on agent + speaking
    local color = get_agent_color(display_agent, display_snap.speaking)
    -- Note: Noctalia widget coloring may be limited, glyph color handled by theme

    -- Tooltip
    local tooltip_lines = {
        display_snap.agent and AGENT_LABELS[display_snap.agent] .. " Status" or "Agent Usage",
        "Quota: " .. quota_text,
    }

    if display_snap.balance then
        table.insert(tooltip_lines, "Balance: " .. format_balance(display_snap.balance))
    end

    if display_snap.quota and display_snap.quota.reset_ms then
        table.insert(tooltip_lines, "Resets in: " .. format_time_ms(display_snap.quota.reset_ms))
    end

    if display_snap.speaking then
        table.insert(tooltip_lines, "● Speaking now")
    end

    if merged.error then
        table.insert(tooltip_lines, "Error: " .. merged.error)
    end

    barWidget.setTooltip(table.concat(tooltip_lines, "\n"))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Event Handlers
-- ─────────────────────────────────────────────────────────────────────────────

function onClick()
    -- Toggle panel based on panel_placement setting
    noctalia.togglePanel(panelId())
end

function onRightClick()
    -- Force refresh
    noctalia.runAsync("noctalia msg plugin roddygithub/agent-usage:collector all refresh", function() end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    load_config()

    -- Initial render with cached state or waiting
    local merged = noctalia.state.get(STATE_KEY_USAGE)
    if merged then
        render(merged)
    else
        barWidget.setGlyph(config.glyph_opencode)
        barWidget.setText("Loading...")
    end

    -- Watch for state changes
    noctalia.state.watch(STATE_KEY_USAGE, function(new_merged)
        render(new_merged)
    end)

    -- Watch speaking state for pulse animation
    noctalia.state.watch("agent_usage_speaking", function(speaking)
        -- Pulse handled by service timers, but widget can react if needed
    end)
end

function shutdown()
    -- Cleanup if needed
end

function update()
    -- Periodic update (driven by state.watch, but keep for interval)
    local merged = noctalia.state.get(STATE_KEY_USAGE)
    if merged then
        render(merged)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry Point
-- ─────────────────────────────────────────────────────────────────────────────

init()