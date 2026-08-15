-- Agent Usage Detail Panel for Noctalia V5
-- Declarative UI panel showing limits, balance, tokens charts, sync status
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local STATE_KEY_USAGE = "agent_usage"
local STATE_KEY_SYNC = "agent_usage_sync"

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function format_quota(quota)
    if not quota or not quota.limit or quota.limit == 0 then
        return quota.used .. " / ∞"
    end
    local pct = math.floor((quota.used / quota.limit) * 100)
    return string.format("%d%% (%d/%d)", pct, quota.used, quota.limit)
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

local function format_tokens(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end

local function agent_color(agent)
    local colors = {
        opencode = "blue",
        claude = "purple",
        codex = "green",
        fireworks = "orange",
    }
    return colors[agent] or "gray"
end

local function agent_label(agent)
    local labels = {
        opencode = "opencode",
        claude = "Claude",
        codex = "Codex",
        fireworks = "Fireworks",
    }
    return labels[agent] or agent
end

local function agent_glyph(agent)
    local glyphs = {
        opencode = "code",
        claude = "bot",
        codex = "terminal",
        fireworks = "flame",
    }
    return glyphs[agent] or "code"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- IPC Actions
-- ─────────────────────────────────────────────────────────────────────────────

local function send_ipc(cmd, args)
    local payload = { cmd = cmd, args = args or {} }
    local json = noctalia.json.encode(payload)
    noctalia.runAsync({ "noctalia", "msg", "plugin", "roddygithub/agent-usage:service", "all", cmd }, function() end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UI Tree Rendering
-- ─────────────────────────────────────────────────────────────────────────────

local function render_hero(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    local speaking = merged.speaking

    local badge_text = "IDLE"
    local badge_color = "gray"
    if snap then
        if snap.speaking then
            badge_text = "SPEAKING"
            badge_color = "pulse"
        elseif snap.quota and snap.quota.limit and snap.quota.limit > 0 then
            local pct = math.floor((snap.quota.used / snap.quota.limit) * 100)
            if pct >= 90 then
                badge_text = "LIMIT"
                badge_color = "red"
            elseif pct >= 70 then
                badge_text = "HIGH"
                badge_color = "orange"
            else
                badge_text = "OK"
                badge_color = "green"
            end
        else
            badge_text = "IDLE"
            badge_color = "gray"
        end
    end

    local plan = snap and snap.plan or "—"
    local auth_status = "Connected"
    if merged.error then
        auth_status = "Error: " .. merged.error
    end

    return {
        type = "box",
        orientation = "horizontal",
        spacing = 12,
        children = {
            {
                type = "badge",
                text = badge_text,
                color = badge_color,
                size = "large",
            },
            {
                type = "box",
                orientation = "vertical",
                spacing = 2,
                grow = true,
                children = {
                    {
                        type = "box",
                        orientation = "horizontal",
                        spacing = 8,
                        children = {
                            { type = "glyph", name = "robot", size = 20 },
                            { type = "text", text = primary and agent_label(primary) or "—", weight = "bold", size = "large" },
                            { type = "badge", text = plan, color = "blue", size = "small" },
                        }
                    },
                    {
                        type = "text",
                        text = auth_status,
                        color = "muted",
                        size = "small",
                    },
                }
            },
            {
                type = "box",
                orientation = "horizontal",
                spacing = 8,
                children = {
                    {
                        type = "button",
                        text = "Refresh",
                        variant = "primary",
                        on_click = "ipc:refresh",
                    },
                    {
                        type = "button",
                        text = "Toggle Sync",
                        variant = "secondary",
                        on_click = "ipc:toggle_sync",
                    },
                }
            },
        }
    }
end

local function render_limits(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.limits or #snap.limits == 0 then
        return {
            type = "text",
            text = "No limit data available",
            color = "muted",
            margin_top = 8,
        }
    end

    local items = {}
    for _, limit in ipairs(snap.limits) do
        local pct = limit.percent or 0
        local color = "green"
        if pct >= 90 then color = "red" elseif pct >= 70 then color = "orange" end

        table.insert(items, {
            type = "card",
            margin_bottom = 8,
            children = {
                {
                    type = "box",
                    orientation = "horizontal",
                    spacing = 8,
                    children = {
                        { type = "text", text = limit.name or "Limit", weight = "bold", grow = true },
                        { type = "badge", text = string.format("%.0f%%", pct), color = color, size = "small" },
                    }
                },
                {
                    type = "box",
                    orientation = "horizontal",
                    spacing = 12,
                    children = {
                        {
                            type = "progress",
                            value = math.floor(pct),
                            max = 100,
                            color = color,
                            grow = true,
                        },
                        {
                            type = "text",
                            text = string.format("%d/%d", limit.used or 0, limit.limit or 0),
                            size = "small",
                            color = "muted",
                        },
                        {
                            type = "text",
                            text = "Reset: " .. (limit.reset_ms and (format_time(limit.reset_ms) .. " left") or "—"),
                            size = "small",
                            color = "muted",
                        },
                    }
                },
            }
        })
    end

    return {
        type = "box",
        orientation = "vertical",
        spacing = 8,
        children = {
            { type = "text", text = "Limites", weight = "bold", size = "large", margin_bottom = 8 },
            { type = "box", orientation = "vertical", spacing = 4, children = items },
        }
    }
end

local function render_balance(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.balance then
        return {
            type = "text",
            text = "Balance data not available",
            color = "muted",
            margin_top = 8,
        }
    end

    local balance = snap.balance
    local credits = balance.credits or 0
    local funded = balance.funded or credits
    local ratio = funded > 0 and credits / funded or 0
    local color = "green"
    if ratio < 0.2 then color = "red" elseif ratio < 0.5 then color = "orange" end

    return {
        type = "box",
        orientation = "vertical",
        spacing = 8,
        children = {
            { type = "text", text = "Balance", weight = "bold", size = "large", margin_bottom = 8 },
            {
                type = "box",
                orientation = "horizontal",
                spacing = 12,
                children = {
                    {
                        type = "gauge",
                        value = math.floor(ratio * 100),
                        max = 100,
                        color = color,
                        size = "large",
                        grow = true,
                    },
                    {
                        type = "box",
                        orientation = "vertical",
                        spacing = 4,
                        children = {
                            { type = "text", text = string.format("$%.2f / $%.2f", credits, funded), weight = "bold" },
                            { type = "text", text = string.format("Spent: $%.2f (%.0f%%)", funded - credits, (1 - ratio) * 100), color = "muted", size = "small" },
                            { type = "text", text = balance.estimated and "Estimated" or "Live", size = "small", color = balance.estimated and "orange" or "green" },
                        }
                    },
                }
            },
        }
    }
end

local function render_tokens_daily(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.tokens_daily or #snap.tokens_daily == 0 then
        return {
            type = "text",
            text = "Daily token data not available",
            color = "muted",
            margin_top = 8,
        }
    end

    -- Simple bar chart using progress bars
    local items = {}
    for _, day in ipairs(snap.tokens_daily) do
        local is_today = day.today or false
        table.insert(items, {
            type = "card",
            margin_bottom = 4,
            children = {
                {
                    type = "box",
                    orientation = "horizontal",
                    spacing = 8,
                    children = {
                        { type = "text", text = day.date or "—", weight = is_today and "bold" or "normal", size = "small", width = 60 },
                        { type = "progress", value = day.percent or 0, max = 100, color = is_today and "blue" or "gray", grow = true },
                        { type = "text", text = format_tokens(day.tokens or 0), size = "small", color = "muted", width = 80 },
                    }
                },
            }
        })
    end

    return {
        type = "box",
        orientation = "vertical",
        spacing = 8,
        children = {
            { type = "text", text = "Tokens / Jour (7j)", weight = "bold", size = "large", margin_bottom = 8 },
            { type = "box", orientation = "vertical", spacing = 4, children = items },
        }
    }
end

local function render_tokens_by_model(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.tokens_by_model or next(snap.tokens_by_model) == nil then
        return {
            type = "text",
            text = "Model breakdown not available",
            color = "muted",
            margin_top = 8,
        }
    end

    -- Sort models by token count descending
    local models = {}
    local total = 0
    for model, count in pairs(snap.tokens_by_model) do
        table.insert(models, { model = model, count = count })
        total = total + count
    end
    table.sort(models, function(a, b) return a.count > b.count end)

    local items = {}
    for _, m in ipairs(models) do
        local pct = total > 0 and math.floor((m.count / total) * 100) or 0
        local type_counts = ""
        if snap.tokens_by_type and snap.tokens_by_type[m.model] then
            local t = snap.tokens_by_type[m.model]
            type_counts = string.format(" (in:%d out:%d cache:%d)", t.input or 0, t.output or 0, t.cache or 0)
        end

        table.insert(items, {
            type = "card",
            margin_bottom = 4,
            children = {
                {
                    type = "box",
                    orientation = "horizontal",
                    spacing = 8,
                    children = {
                        { type = "text", text = m.model, weight = "bold", grow = true },
                        { type = "badge", text = pct .. "%", color = "blue", size = "small" },
                        { type = "text", text = format_tokens(m.count) .. type_counts, size = "small", color = "muted" },
                    }
                },
                {
                    type = "progress",
                    value = pct,
                    max = 100,
                    color = "blue",
                },
            }
        })
    end

    return {
        type = "box",
        orientation = "vertical",
        spacing = 8,
        children = {
            { type = "text", text = "Tokens / Modèle", weight = "bold", size = "large", margin_bottom = 8 },
            { type = "text", text = "Total: " .. format_tokens(total), color = "muted", size = "small", margin_bottom = 8 },
            { type = "box", orientation = "vertical", spacing = 4, children = items },
        }
    }
end

local function render_sync(merged)
    local sync_mode = "Off"
    local sync_dir = ""
    local last_sync = "—"
    local devices = 0

    -- Get sync config from service (would need to be published separately)
    -- For now, read from merged sync state if available
    if merged.sync then
        sync_mode = merged.sync.mode or "Off"
        sync_dir = merged.sync.dir or ""
        last_sync = merged.sync.last_sync and format_time(merged.sync.last_sync) or "—"
        devices = merged.sync.devices or 0
    end

    local status_text = sync_mode == "On" and "Activé" or "Désactivé"
    local status_color = sync_mode == "On" and "green" or "gray"

    return {
        type = "box",
        orientation = "vertical",
        spacing = 8,
        children = {
            { type = "text", text = "Sync Multi-Machine", weight = "bold", size = "large", margin_bottom = 8 },
            {
                type = "box",
                orientation = "horizontal",
                spacing = 12,
                children = {
                    { type = "badge", text = status_text, color = status_color, size = "large" },
                    { type = "text", text = "Dossier: " .. (sync_dir ~= "" and sync_dir or "—"), color = "muted", grow = true },
                }
            },
            {
                type = "box",
                orientation = "horizontal",
                spacing = 12,
                children = {
                    { type = "text", text = "Dernière sync: " .. last_sync, color = "muted" },
                    { type = "text", text = "Appareils: " .. devices, color = "muted" },
                }
            },
            {
                type = "box",
                orientation = "horizontal",
                spacing = 8,
                children = {
                    { type = "button", text = "Forcer Sync", variant = "primary", on_click = "ipc:force_sync" },
                    { type = "button", text = sync_mode == "On" and "Désactiver" or "Activer", variant = "secondary", on_click = "ipc:toggle_sync" },
                }
            },
        }
    }
end

local function render_full_panel(merged)
    return {
        type = "scroll",
        children = {
            render_hero(merged),
            { type = "separator", margin_top = 16, margin_bottom = 16 },
            render_limits(merged),
            { type = "separator", margin_top = 16, margin_bottom = 16 },
            render_balance(merged),
            { type = "separator", margin_top = 16, margin_bottom = 16 },
            render_tokens_daily(merged),
            { type = "separator", margin_top = 16, margin_bottom = 16 },
            render_tokens_by_model(merged),
            { type = "separator", margin_top = 16, margin_bottom = 16 },
            render_sync(merged),
        }
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function init()
    -- Initial render
    local merged = noctalia.state.get("agent_usage") or { primary_agent = nil, agents = {}, speaking = false }
    panel.render(render_full_panel(merged))

    -- Watch for updates
    noctalia.state.watch("agent_usage", function(new_merged)
        panel.render(render_full_panel(new_merged))
    end)

    -- Watch sync state if available
    noctalia.state.watch("agent_usage_sync", function(new_sync)
        local merged = noctalia.state.get("agent_usage") or {}
        merged.sync = new_sync
        panel.render(render_full_panel(merged))
    end)
end

function shutdown()
    -- Cleanup
end

function update()
    -- Periodic refresh handled by state watches
end

init()