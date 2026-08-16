-- Agent Usage Detail Panel for Noctalia V5
-- Declarative UI panel (ui.* tree) showing limits, balance, tokens charts, sync
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local STATE_KEY_USAGE = "agent_usage"
local STATE_KEY_SYNC = "agent_usage_sync"

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function format_quota(quota)
    if not quota then return "—" end
    if quota.percent ~= nil then
        return string.format("%d%%", quota.percent)
    end
    if not quota.limit or quota.limit == 0 then
        return quota.used .. " / ∞"
    end
    local pct = math.floor((quota.used / quota.limit) * 100)
    return string.format("%d%% (%d/%d)", pct, quota.used, quota.limit)
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
        ["opencode-zen"] = "green",
        openrouter = "cyan",
    }
    return colors[agent] or "gray"
end

local function agent_label(agent)
    local labels = {
        opencode = "opencode",
        claude = "Claude",
        codex = "Codex",
        fireworks = "Fireworks",
        ["opencode-zen"] = "OpenCode Zen",
        openrouter = "OpenRouter",
    }
    return labels[agent] or agent
end

local function agent_glyph(agent)
    local glyphs = {
        opencode = "terminal",
        claude = "bot",
        codex = "database",
        fireworks = "flame",
        ["opencode-zen"] = "sparkles",
        openrouter = "route",
    }
    return glyphs[agent] or "terminal"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Sections
-- ─────────────────────────────────────────────────────────────────────────────

local function render_hero(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    local badge_text = "IDLE"
    local badge_color = "gray"
    if snap then
        if snap.speaking then
            badge_text = "SPEAKING"
            badge_color = "secondary"
        elseif snap.quota and snap.quota.limit and snap.quota.limit > 0 then
            local pct = math.floor((snap.quota.used / snap.quota.limit) * 100)
            if pct >= 90 then
                badge_text = "LIMIT"
                badge_color = "error"
            elseif pct >= 70 then
                badge_text = "HIGH"
                badge_color = "warning"
            else
                badge_text = "OK"
                badge_color = "success"
            end
        end
    end

    local plan = snap and snap.plan or "—"
    local quota_text = snap and snap.quota and format_quota(snap.quota) or "—"
    local auth_status = merged.error and ("Error: " .. merged.error) or "Connected"

    return ui.column({ gap = 8, padding = 12, radius = 8, fill = "surface/0.5" }, {
        ui.row({ gap = 8, align = "center" }, {
            ui.glyph({ name = snap and agent_glyph(primary) or "terminal", size = 20, color = "primary" }),
            ui.label({ text = snap and agent_label(primary) or "No agent", fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
            ui.label({ text = badge_text, fontSize = 11, fontWeight = "bold", color = badge_color }),
        }),
        ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = "Plan: " .. plan, fontSize = 12, color = "on_surface_variant" }),
            ui.label({ text = quota_text, fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
        }),
        ui.label({ text = auth_status, fontSize = 11, color = "on_surface_variant" }),
    })
end

local function render_limits(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.limits or #snap.limits == 0 then
        return ui.label({ text = "No limit data available", fontSize = 12, color = "on_surface_variant" })
    end

    local items = {}
    for _, limit in ipairs(snap.limits) do
        local pct = limit.percent or 0
        local color = "success"
        if pct >= 90 then color = "error" elseif pct >= 70 then color = "warning" end

        table.insert(items, ui.column({ gap = 4, fill = "surface/0.5", radius = 8, padding = 8 }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.label({ text = limit.name or "Limit", fontSize = 12, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
                ui.label({ text = string.format("%.0f%%", pct), fontSize = 11, fontWeight = "bold", color = color }),
            }),
            ui.row({ gap = 8, align = "center" }, {
                ui.progress({ value = math.floor(pct), max = 100, color = color, flexGrow = 1 }),
                ui.label({ text = string.format("%d/%d", limit.used or 0, limit.limit or 0), fontSize = 11, color = "on_surface_variant" }),
            }),
            ui.label({
                text = "Reset: " .. (limit.reset_ms and (format_time_ms(limit.reset_ms) .. " left") or "—"),
                fontSize = 11,
                color = "on_surface_variant",
            }),
        }))
    end

    return ui.column({ gap = 8, padding = 8 }, {
        ui.label({ text = "Limites", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.column({ gap = 6, children = items }),
    })
end

local function render_balance(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.balance then
        return ui.label({ text = "Balance data not available", fontSize = 12, color = "on_surface_variant" })
    end

    local balance = snap.balance
    local credits = balance.credits or 0
    local funded = balance.funded or credits
    local ratio = funded > 0 and credits / funded or 0
    local color = "success"
    if ratio < 0.2 then color = "error" elseif ratio < 0.5 then color = "warning" end

    return ui.column({ gap = 8, padding = 8 }, {
        ui.label({ text = "Balance", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.column({ gap = 6, fill = "surface/0.5", radius = 8, padding = 8 }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.label({ text = string.format("$%.2f / $%.2f", credits, funded), fontSize = 13, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
                ui.label({ text = string.format("(%.0f%%)", ratio * 100), fontSize = 11, fontWeight = "bold", color = color }),
            }),
            ui.progress({ value = math.floor(ratio * 100), max = 100, color = color }),
            ui.label({ text = string.format("Spent: $%.2f", funded - credits), fontSize = 11, color = "on_surface_variant" }),
            ui.label({ text = balance.estimated and "Estimated" or "Live", fontSize = 11, color = balance.estimated and "warning" or "success" }),
        }),
    })
end

local function render_tokens_daily(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.tokens_daily or #snap.tokens_daily == 0 then
        return ui.label({ text = "Daily token data not available", fontSize = 12, color = "on_surface_variant" })
    end

    local items = {}
    for _, day in ipairs(snap.tokens_daily) do
        local is_today = day.today or false
        table.insert(items, ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = day.date or "—", fontSize = 11, fontWeight = is_today and "bold" or "normal", color = "on_surface", width = 60 }),
            ui.progress({ value = day.percent or 0, max = 100, color = is_today and "primary" or "on_surface_variant", flexGrow = 1 }),
            ui.label({ text = format_tokens(day.tokens or 0), fontSize = 11, color = "on_surface_variant", width = 70 }),
        }))
    end

    return ui.column({ gap = 8, padding = 8 }, {
        ui.label({ text = "Tokens / Jour (7j)", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.column({ gap = 4, children = items }),
    })
end

local function render_tokens_by_model(merged)
    local primary = merged.primary_agent
    local snap = primary and merged.agents[primary]
    if not snap or not snap.tokens_by_model or next(snap.tokens_by_model) == nil then
        return ui.label({ text = "Model breakdown not available", fontSize = 12, color = "on_surface_variant" })
    end

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

        table.insert(items, ui.column({ gap = 4 }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.label({ text = m.model, fontSize = 12, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
                ui.label({ text = pct .. "%", fontSize = 11, fontWeight = "bold", color = "primary" }),
                ui.label({ text = format_tokens(m.count) .. type_counts, fontSize = 11, color = "on_surface_variant" }),
            }),
            ui.progress({ value = pct, max = 100, color = "primary" }),
        }))
    end

    return ui.column({ gap = 8, padding = 8 }, {
        ui.label({ text = "Tokens / Modèle", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = "Total: " .. format_tokens(total), fontSize = 11, color = "on_surface_variant" }),
        ui.column({ gap = 8, children = items }),
    })
end

local function render_sync(merged)
    local sync_mode = "Off"
    local sync_dir = ""
    local last_sync = "—"
    local devices = {}
    local device_count = 0

    if merged.sync then
        sync_mode = merged.sync.mode or "Off"
        sync_dir = merged.sync.dir or ""
        last_sync = merged.sync.last_sync and format_time_ms(merged.sync.last_sync) or "—"
        devices = merged.sync.devices or {}
        device_count = #devices
    end

    local status_text = sync_mode == "On" and "Activé" or "Désactivé"
    local status_color = sync_mode == "On" and "success" or "on_surface_variant"

    local children = {
        ui.label({ text = "Sync Multi-Machine", fontSize = 14, fontWeight = "bold", color = "on_surface" }),
        ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = status_text, fontSize = 12, fontWeight = "bold", color = status_color }),
            ui.label({ text = "Dossier: " .. (sync_dir ~= "" and sync_dir or "—"), fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
        }),
        ui.row({ gap = 12 }, {
            ui.label({ text = "Dernière sync: " .. last_sync, fontSize = 11, color = "on_surface_variant" }),
            ui.label({ text = "Appareils: " .. device_count, fontSize = 11, color = "on_surface_variant" }),
        }),
    }

    local device_items = {}
    for _, dev in ipairs(devices) do
        table.insert(device_items, ui.row({ gap = 8, align = "center" }, {
            ui.label({ text = dev.id, fontSize = 12, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
            ui.label({ text = "Agent: " .. (dev.primary_agent or "—"), fontSize = 11, color = "on_surface_variant" }),
            ui.label({ text = "Vu: " .. (dev.last_seen and format_time_ms(dev.last_seen) or "—"), fontSize = 11, color = "on_surface_variant" }),
        }))
    end

    if device_count > 0 then
        table.insert(children, ui.column({ gap = 4 }, {
            ui.label({ text = "Appareils connectés:", fontSize = 11, fontWeight = "bold", color = "on_surface" }),
            ui.column({ gap = 2, children = device_items }),
        }))
    else
        table.insert(children, ui.label({ text = "Aucun appareil connecté", fontSize = 11, color = "on_surface_variant" }))
    end

    return ui.column({ gap = 8, padding = 8 }, children)
end

local function render_full_panel(merged)
    return ui.scroll({ flexGrow = 1, gap = 14, padding = 16 }, {
        ui.column({ gap = 14, radius = 12, fill = "surface/0.8", border = "on_surface/0.1", borderWidth = 1, padding = 8 }, {
            render_hero(merged),
            ui.separator({}),
            render_limits(merged),
            ui.separator({}),
            render_balance(merged),
            ui.separator({}),
            render_tokens_daily(merged),
            ui.separator({}),
            render_tokens_by_model(merged),
            ui.separator({}),
            render_sync(merged),
        }),
    })
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

local function render()
    local merged = noctalia.state.get(STATE_KEY_USAGE) or { primary_agent = nil, agents = {}, speaking = false }
    panel.render(render_full_panel(merged))
end

function init()
    -- Watch for updates (panel entry may be loaded before the service publishes)
    noctalia.state.watch(STATE_KEY_USAGE, render)
    noctalia.state.watch(STATE_KEY_SYNC, render)
end

function onOpen(_context)
    render()
end

function shutdown()
    -- Cleanup
end

function update()
    -- Periodic refresh handled by state watches
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Entry Point
-- ─────────────────────────────────────────────────────────────────────────────

init()