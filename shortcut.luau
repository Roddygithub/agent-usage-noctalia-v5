-- Agent Usage Control Center Shortcut for Noctalia V5
-- Quick toggle tile in Control Center
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local STATE_KEY_USAGE = "agent_usage"
local STATE_KEY_SPEAKING = "agent_usage_speaking"

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local AGENT_LABELS = {
    opencode = "opencode",
    claude = "Claude",
    codex = "Codex",
    fireworks = "Fireworks",
    ["opencode-zen"] = "OpenCode Zen",
    openrouter = "OpenRouter",
}

local AGENT_GLYPHS = {
    opencode = "terminal",
    claude = "bot",
    codex = "database",
    fireworks = "flame",
    ["opencode-zen"] = "sparkles",
    openrouter = "route",
}

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
-- Rendering
-- ─────────────────────────────────────────────────────────────────────────────

local function render(merged, speaking)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]

    local active = speaking == true
    shortcut.setActive(active)

    local glyph, label
    if active then
        glyph = "pause"
        label = "Pause"
    else
        if primary then
            glyph = AGENT_GLYPHS[primary] or "code"
            label = AGENT_LABELS[primary] or primary
            if snap and snap.quota and snap.quota.limit and snap.quota.limit > 0 then
                local pct = math.floor((snap.quota.used / snap.quota.limit) * 100)
                label = label .. " " .. pct .. "%"
            end
        else
            glyph = "robot"
            label = "No agents"
        end
    end

    shortcut.setGlyph(glyph)
    shortcut.setLabel(label)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Event Handlers
-- ─────────────────────────────────────────────────────────────────────────────

function onClick()
    -- Toggle panel based on panel_placement setting
    noctalia.togglePanel(panelId())
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    -- Initial render
    local merged = noctalia.state.get("agent_usage") or { primary_agent = nil, agents = {}, speaking = false }
    local speaking = noctalia.state.get("agent_usage_speaking") or false
    render(merged, speaking)

    -- Watch for changes
    noctalia.state.watch("agent_usage", function(new_merged)
        local speaking = noctalia.state.get("agent_usage_speaking") or false
        render(new_merged, speaking)
    end)

    noctalia.state.watch("agent_usage_speaking", function(new_speaking)
        local merged = noctalia.state.get("agent_usage") or { primary_agent = nil, agents = {} }
        render(merged, new_speaking)
    end)
end

function shutdown()
    -- Cleanup if needed
end

function update()
    -- Periodic refresh
    local merged = noctalia.state.get("agent_usage") or { primary_agent = nil, agents = {} }
    local speaking = noctalia.state.get("agent_usage_speaking") or false
    render(merged, speaking)
end

init()