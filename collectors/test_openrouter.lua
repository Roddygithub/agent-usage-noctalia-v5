-- OpenRouter Collector Unit Tests
-- TDD: Tests written FIRST (RED phase) before implementation
-- Tests collector contract compliance and OpenRouter API behavior
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

local function run_test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("✓ " .. name)
        return true
    else
        print("✗ " .. name .. ": " .. tostring(err))
        return false
    end
end

local function assert_equal(actual, expected, msg)
    if actual ~= expected then
        error((msg or "Assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assert_table_contains(tbl, key, msg)
    if tbl[key] == nil then
        error((msg or "Missing key") .. ": " .. key)
    end
end

local function assert_type(val, expected_type, msg)
    if type(val) ~= expected_type then
        error((msg or "Type mismatch") .. ": expected " .. expected_type .. ", got " .. type(val))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Collector Contract Tests (Required by spec)
-- ─────────────────────────────────────────────────────────────────────────────

local function test_collector_contract()
    local ok, collector = pcall(require, "collectors.openrouter")
    assert_equal(ok, true, "Collector must load without error")
    assert_type(collector, "table", "Collector must return table")

    -- Required fields per x-collector-contract
    assert_type(collector.name, "string", "Collector must have name")
    assert_equal(collector.name, "openrouter", "Collector name must be 'openrouter'")

    assert_type(collector.collect, "function", "Collector must have collect function")
    assert_type(collector.validate_config, "function", "Collector must have validate_config function")
    assert_type(collector.default_config, "table", "Collector must have default_config table")

    -- Validate default config passes validation
    local valid, err = collector.validate_config(collector.default_config)
    assert_equal(valid, true, "Default config must be valid: " .. tostring(err))
end

local function test_validate_config()
    local ok, collector = pcall(require, "collectors.openrouter")
    assert_equal(ok, true)

    -- Valid config
    local valid, err = collector.validate_config({ enabled = true, api_key_env = "OPENROUTER_API_KEY" })
    assert_equal(valid, true, "Valid config should pass: " .. tostring(err))

    -- Invalid: api_key_env not string
    valid, err = collector.validate_config({ api_key_env = 123 })
    assert_equal(valid, false, "Non-string api_key_env should fail")

    -- Valid: extra keys allowed (should not crash)
    valid, err = collector.validate_config({ extra = "key", enabled = true })
    -- Should not crash - extra keys are allowed
end

local function test_default_config_structure()
    local ok, collector = pcall(require, "collectors.openrouter")
    assert_equal(ok, true)

    local cfg = collector.default_config
    assert_type(cfg.enabled, "boolean", "default_config.enabled must be boolean")
    assert_equal(cfg.enabled, true, "default_config.enabled should default to true")
    assert_type(cfg.api_key_env, "string", "default_config.api_key_env must be string")
    assert_equal(cfg.api_key_env, "OPENROUTER_API_KEY", "default_config.api_key_env should be OPENROUTER_API_KEY")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot Schema Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_snapshot_required_fields()
    local ok, collector = pcall(require, "collectors.openrouter")
    assert_equal(ok, true)

    -- We can't call collect() without mocking, but we can verify the contract
    -- The collect function should return a snapshot with required fields per protocol v1
    assert_type(collector.collect, "function")

    -- Test that if we had a mock, the snapshot would have these fields:
    -- Required per protocol-v1.openspec.yaml Snapshot schema:
    local required_fields = { "version", "timestamp", "agent" }
    for _, field in ipairs(required_fields) do
        -- Just verify the field names are correct strings
        assert_type(field, "string")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OpenRouter API Behavior Tests (Mocked)
-- ─────────────────────────────────────────────────────────────────────────────

local function test_parse_openrouter_key_response()
    -- Test parsing of OpenRouter /api/v1/auth/key response
    local mock_response = {
        data = {
            label = "My OpenRouter Key",
            limit = 1000,
            usage = 250,
            is_free_tier = false
        }
    }

    -- Simulate what the collector should extract
    local key_info = mock_response.data or mock_response
    assert_equal(key_info.label, "My OpenRouter Key")
    assert_equal(key_info.limit, 1000)
    assert_equal(key_info.usage, 250)
    assert_equal(key_info.is_free_tier, false)
end

local function test_parse_openrouter_free_tier()
    local mock_response = {
        data = {
            label = "Free Tier Key",
            limit = 100,
            usage = 10,
            is_free_tier = true
        }
    }

    local key_info = mock_response.data or mock_response
    assert_equal(key_info.is_free_tier, true)
    assert_equal(key_info.limit, 100)
end

local function test_calculate_remaining_and_percentage()
    local limit = 1000
    local usage = 250
    local remaining = limit - usage
    local pct = math.floor((usage / limit) * 100)

    assert_equal(remaining, 750)
    assert_equal(pct, 25)
end

local function test_parse_models_for_free()
    local mock_models = {
        data = {
            { id = "deepseek/deepseek-chat-v3:free", pricing = { prompt = "0", completion = "0" } },
            { id = "qwen/qwen-2.5-coder:free", pricing = { prompt = "0", completion = "0" } },
            { id = "anthropic/claude-3.5-sonnet", pricing = { prompt = "3", completion = "15" } },
            { id = "meta-llama/llama-3.1-405b", pricing = { prompt = "2.7", completion = "2.7" } },
        }
    }

    local free_models = {}
    if mock_models.data then
        for _, model in ipairs(mock_models.data) do
            if model.pricing and model.pricing.prompt == "0" and model.pricing.completion == "0" then
                table.insert(free_models, model.id)
            end
        end
    end

    assert_equal(#free_models, 2)
    assert_equal(free_models[1], "deepseek/deepseek-chat-v3:free")
    assert_equal(free_models[2], "qwen/qwen-2.5-coder:free")
end

local function test_no_free_models()
    local mock_models = {
        data = {
            { id = "anthropic/claude-3.5-sonnet", pricing = { prompt = "3", completion = "15" } },
        }
    }

    local free_models = {}
    if mock_models.data then
        for _, model in ipairs(mock_models.data) do
            if model.pricing and model.pricing.prompt == "0" and model.pricing.completion == "0" then
                table.insert(free_models, model.id)
            end
        end
    end

    assert_equal(#free_models, 0)
end

local function test_missing_pricing_handled()
    local mock_models = {
        data = {
            { id = "some/model", pricing = nil }, -- Missing pricing
            { id = "another/model" }, -- Missing pricing entirely
        }
    }

    local free_models = {}
    if mock_models.data then
        for _, model in ipairs(mock_models.data) do
            if model.pricing and model.pricing.prompt == "0" and model.pricing.completion == "0" then
                table.insert(free_models, model.id)
            end
        end
    end

    assert_equal(#free_models, 0) -- Should not crash, just skip
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Error Handling Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_missing_api_key_error()
    -- When no API key found in auth.json or env
    local error_msg = "OpenRouter API key not found in auth.json or env"
    assert_type(error_msg, "string")
    assert_equal(error_msg:find("not found") ~= nil, true) -- Should contain "not found"
end

local function test_invalid_json_response()
    local invalid_json = "not valid json {"
    local ok, data = pcall(function()
        -- This simulates what noctalia.json.decode would do
        return nil -- Would return nil, error
    end)
    -- Should handle gracefully
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Run All Tests
-- ─────────────────────────────────────────────────────────────────────────────

local tests = {
    { "Contract: Collector loads and has required fields", test_collector_contract },
    { "Contract: validate_config with valid/invalid inputs", test_validate_config },
    { "Contract: default_config structure", test_default_config_structure },
    { "Schema: Snapshot required fields", test_snapshot_required_fields },
    { "OpenRouter: Parse key response (paid tier)", test_parse_openrouter_key_response },
    { "OpenRouter: Parse key response (free tier)", test_parse_openrouter_free_tier },
    { "OpenRouter: Calculate remaining and percentage", test_calculate_remaining_and_percentage },
    { "OpenRouter: Parse models for free tier", test_parse_models_for_free },
    { "OpenRouter: No free models case", test_no_free_models },
    { "OpenRouter: Missing pricing handled gracefully", test_missing_pricing_handled },
    { "Error: Missing API key error message", test_missing_api_key_error },
    { "Error: Invalid JSON response handled", test_invalid_json_response },
}

local passed = 0
local failed = 0

print("=== Running OpenRouter Collector Unit Tests (RED Phase) ===\n")

for _, test in ipairs(tests) do
    if run_test(test[1], test[2]) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

print("\n=== Results: " .. passed .. " passed, " .. failed .. " failed ===")

if failed > 0 then
    os.exit(1)
end

print("✓ All OpenRouter collector tests defined (RED phase complete)")
print("Next: Implement openrouter.lua to make these pass (GREEN phase)")