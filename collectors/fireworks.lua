-- Fireworks Collector for Agent Usage Monitor
-- Reads ~/.config/agent-usage/fireworks.json + optional Billing API
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local function now_ms()
    return os.time() * 1000
end

local M = {
    name = "fireworks",
    default_config = {
        enabled = true,
        api_key_env = "FIREWORKS_API_KEY",
        config_path = "~/.config/agent-usage/fireworks.json",
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Config Validation
-- ─────────────────────────────────────────────────────────────────────────────

function M.validate_config(cfg)
    if not cfg then return true, nil end
    if cfg.api_key_env and type(cfg.api_key_env) ~= "string" then
        return false, "api_key_env must be string"
    end
    if cfg.config_path and type(cfg.config_path) ~= "string" then
        return false, "config_path must be string"
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Local Config Reading
-- ─────────────────────────────────────────────────────────────────────────────

local function read_local_config(config)
    local path = expand_path(config.config_path or "~/.config/agent-usage/fireworks.json")
    local data, err = read_json_file(path)
    if not data then
        return nil, "Failed to read Fireworks config: " .. tostring(err)
    end

    -- Expected config structure:
    -- {
    --   "account_id": "acct_123",
    --   "funded_amount": 20.00,
    --   "funded_at": "2024-01-01",
    --   "model_rates": {
    --     "llama-v3p1-70b-instruct": { "input": 0.0002, "output": 0.0002 },
    --     "llama-v3p1-8b-instruct": { "input": 0.00005, "output": 0.00005 }
    --   }
    -- }

    local funded_amount = data.funded_amount or 0
    local funded_at = data.funded_at or os.date("%Y-%m-%d")
    local model_rates = data.model_rates or {}

    return {
        funded_amount = funded_amount,
        funded_at = funded_at,
        model_rates = model_rates,
        account_id = data.account_id,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Billing API Call (Optional)
-- ─────────────────────────────────────────────────────────────────────────────

local function fetch_billing_api(config, local_config)
    local api_key = os.getenv(config.api_key_env or "FIREWORKS_API_KEY")
    if not api_key then
        return nil, "FIREWORKS_API_KEY not set"
    end

    local account_id = local_config.account_id
    if not account_id then
        return nil, "account_id not configured"
    end

    -- Fireworks billing API endpoint
    -- GET https://api.fireworks.ai/v1/accounts/{account_id}/usage
    -- Headers: Authorization: Bearer {api_key}

    local url = "https://api.fireworks.ai/v1/accounts/" .. account_id .. "/usage"
    local cmd = {
        "curl", "-s", "-H", "Authorization: Bearer " .. api_key,
        "-H", "Accept: application/json",
        url
    }

    -- This would need runAsync with HTTP - for now return nil to use local estimate
    return nil, "API call not implemented, using local estimate"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Collection Function
-- ─────────────────────────────────────────────────────────────────────────────

function M.collect(config)
    config = config or M.default_config

    -- Read local config for funded amount and rates
    local local_config, err = read_local_config(config)
    if not local_config then
        return nil, "Failed to read local Fireworks config: " .. tostring(err)
    end

    -- Try to fetch live billing data
    local billing_data, api_err = fetch_billing_api(config, local_config)
    local spent = 0
    local tokens_by_model = {}
    local tokens_by_type = { input = 0, output = 0, cache = 0 }
    local daily_usage = {}

    if billing_data then
        -- Parse billing API response
        -- Expected: { "usage": [ { "model": "...", "input_tokens": 1000, "output_tokens": 500, "cost": 0.001, "timestamp": "..." }, ... ] }
        spent = billing_data.total_cost or 0
        if billing_data.usage then
            for _, usage in ipairs(billing_data.usage) do
                local model = usage.model or "unknown"
                local input = usage.input_tokens or 0
                local output = usage.output_tokens or 0
                local cache = usage.cache_tokens or 0
                tokens_by_model[model] = (tokens_by_model[model] or 0) + input + output
                -- Daily aggregation would go here
            end
        end
    else
        -- Use local estimate: funded - estimated spent based on model rates
        -- This is a rough estimate since we don't have actual usage without API
        if noctalia and noctalia.log then
            noctalia.log("[agent-usage] WARN: Fireworks API unavailable: " .. tostring(api_err) .. ", using local estimate")
        end
    end

    -- For now, create a basic snapshot with estimated balance
    local funded = local_config.funded_amount or 0
    local balance_credits = math.max(0, funded - spent)

    local snapshot = {
        version = 1,
        timestamp = now_ms(),
        agent = "fireworks",
        plan = "Prepaid",
        quota = nil, -- Fireworks uses prepaid credits, not quota
        balance = {
            credits = balance_credits,
            currency = "USD",
            estimated = not billing_data,
        },
        speaking = false,
        tokens_today = 0, -- Would need daily aggregation
        tokens_by_model = tokens_by_model,
        tokens_by_type = tokens_by_type,
        tokens_daily = daily_usage,
        limits = {},
    }

    -- Add balance as a "limit" for display purposes
    if funded > 0 then
        local pct = funded > 0 and math.floor((balance_credits / funded) * 100) or 100
        table.insert(snapshot.limits, {
            name = "Prepaid balance",
            used = spent,
            limit = funded,
            reset_ms = 0,
            percent = pct,
        })
    end

    return snapshot
end

return M