-- Protocol Round-trip Test for Agent Usage Monitor
-- Tests: TypeScript encode → Lua decode → verify schema
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

-- Mock noctalia.json for testing (not available outside Noctalia runtime)
local json = require("dkjson")
noctalia = {
    json = {
        encode = json.encode,
        decode = json.decode,
    }
}

local function now_ms()
    return os.time() * 1000
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Test Cases: Simulate TypeScript → JSON → Lua round-trip
-- ─────────────────────────────────────────────────────────────────────────────

local function test_basic_snapshot()
    -- Simulate what TypeScript would produce
    local ts_snapshot = {
        version = 1,
        timestamp = 1692000000000,
        agent = "opencode",
        plan = "Free",
        quota = {
            used = 15000,
            limit = 50000,
            reset_ms = 1692086400000,
            period = "day",
        },
        balance = {
            credits = 10.50,
            currency = "USD",
            estimated = false,
        },
        speaking = false,
        tokens_today = 15000,
        tokens_by_model = {
            ["gpt-4o"] = 10000,
            ["gpt-4o-mini"] = 5000,
        },
        tokens_by_type = {
            input = 10000,
            output = 4000,
            cache = 1000,
        },
        limits = {
            { name = "Daily", used = 15000, limit = 50000, reset_ms = 1692086400000, percent = 30 },
        },
    }

    -- Encode to JSON (simulating TypeScript JSON.stringify)
    local json_str = noctalia.json.encode(ts_snapshot)
    assert_table_contains({json_str=json_str}, "json_str")

    -- Decode in Lua (simulating Lua consumer)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true, "JSON decode failed")

    -- Verify all fields preserved
    assert_equal(decoded.version, 1)
    assert_equal(decoded.agent, "opencode")
    assert_equal(decoded.plan, "Free")
    assert_equal(decoded.quota.used, 15000)
    assert_equal(decoded.quota.limit, 50000)
    assert_equal(decoded.quota.reset_ms, 1692086400000)
    assert_equal(decoded.quota.period, "day")
    assert_equal(decoded.balance.credits, 10.50)
    assert_equal(decoded.balance.currency, "USD")
    assert_equal(decoded.balance.estimated, false)
    assert_equal(decoded.speaking, false)
    assert_equal(decoded.tokens_today, 15000)
    assert_equal(decoded.tokens_by_model["gpt-4o"], 10000)
    assert_equal(decoded.tokens_by_model["gpt-4o-mini"], 5000)
    assert_equal(decoded.tokens_by_type.input, 10000)
    assert_equal(decoded.tokens_by_type.output, 4000)
    assert_equal(decoded.tokens_by_type.cache, 1000)
    assert_equal(#decoded.limits, 1)
    assert_equal(decoded.limits[1].name, "Daily")
    assert_equal(decoded.limits[1].percent, 30)
end

local function test_all_agents()
    local agents = { "opencode", "claude", "codex", "fireworks" }
    local base_time = 1692000000000

    for i, agent in ipairs(agents) do
        local snap = {
            version = 1,
            timestamp = base_time + i * 1000,
            agent = agent,
            plan = "Free",
            quota = { used = i * 1000, limit = 10000, reset_ms = 1692086400000, period = "day" },
            balance = nil,
            speaking = false,
            tokens_today = i * 1000,
            tokens_by_model = { ["model-" .. agent] = i * 1000 },
            tokens_by_type = { input = i * 500, output = i * 500 },
            limits = { { name = "Daily", used = i * 1000, limit = 10000, reset_ms = 1692086400000, percent = math.floor(i * 10) } },
        }

        local json_str = noctalia.json.encode(snap)
        local ok, decoded = pcall(noctalia.json.decode, json_str)
        assert_equal(ok, true, "Decode failed for " .. agent)
        assert_equal(decoded.agent, agent)
        assert_equal(decoded.timestamp, base_time + i * 1000)
    end
end

local function test_optional_fields()
    -- Test snapshot with minimal required fields only
    local minimal = {
        version = 1,
        timestamp = 1692000000000,
        agent = "opencode",
    }

    local json_str = noctalia.json.encode(minimal)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)
    assert_equal(decoded.version, 1)
    assert_equal(decoded.agent, "opencode")
    assert_equal(decoded.plan, nil)
    assert_equal(decoded.quota, nil)
    assert_equal(decoded.balance, nil)
    assert_equal(decoded.speaking, nil)
end

local function test_nested_objects()
    -- Test deeply nested structures
    local snap = {
        version = 1,
        timestamp = 1692000000000,
        agent = "claude",
        plan = "Pro",
        quota = {
            used = 100000,
            limit = 1000000,
            reset_ms = 1692086400000,
            period = "day",
        },
        balance = {
            credits = 50.00,
            currency = "USD",
            estimated = false,
        },
        speaking = true,
        tokens_today = 50000,
        tokens_by_model = {
            ["claude-3-opus"] = 100000,
            ["claude-3-sonnet"] = 200000,
        },
        tokens_by_type = {
            input = 150000,
            output = 100000,
            cache = 50000,
        },
        limits = {
            { name = "Daily", used = 100000, limit = 1000000, reset_ms = 1692086400000, percent = 10 },
            { name = "Weekly", used = 500000, limit = 5000000, reset_ms = 1692172800000, percent = 10 },
        },
    }

    local json_str = noctalia.json.encode(snap)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)

    -- Verify nested structure
    assert_equal(decoded.quota.used, 100000)
    assert_equal(decoded.balance.credits, 50.00)
    assert_equal(decoded.balance.estimated, false)
    assert_equal(decoded.tokens_by_model["claude-3-opus"], 100000)
    assert_equal(decoded.tokens_by_type.input, 150000)
    assert_equal(#decoded.limits, 2)
    assert_equal(decoded.limits[1].name, "Daily")
    assert_equal(decoded.limits[2].name, "Weekly")
end

local function test_special_values()
    -- Test null/optional fields
    local snap = {
        version = 1,
        timestamp = 1692000000000,
        agent = "fireworks",
        plan = "Prepaid",
        quota = nil,
        balance = {
            credits = 0,
            currency = "USD",
            estimated = true,
        },
        speaking = false,
        tokens_today = 0,
        tokens_by_model = {},
        tokens_by_type = { input = 0, output = 0, cache = 0 },
        limits = {
            { name = "Balance", used = 0, limit = 20, reset_ms = 0, percent = 100 },
        },
    }

    local json_str = noctalia.json.encode(snap)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)
    assert_equal(decoded.quota, nil)
    assert_equal(decoded.balance.credits, 0)
    assert_equal(decoded.balance.estimated, true)
    assert_equal(#decoded.tokens_by_model, 0)
end

local function test_timestamp_precision()
    -- Test millisecond precision timestamps
    local now_ms = now_ms()
    local snap = {
        version = 1,
        timestamp = now_ms,
        agent = "opencode",
    }

    local json_str = noctalia.json.encode(snap)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)
    assert_equal(decoded.timestamp, now_ms)
end

local function test_unicode()
    -- Test Unicode in model names
    local snap = {
        version = 1,
        timestamp = 1692000000000,
        agent = "opencode",
        tokens_by_model = {
            ["gpt-4o"] = 1000,
            ["模型-测试"] = 500,
            ["🤖-model"] = 100,
        },
    }

    local json_str = noctalia.json.encode(snap)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)
    assert_equal(decoded.tokens_by_model["模型-测试"], 500)
    assert_equal(decoded.tokens_by_model["🤖-model"], 100)
end

local function test_large_numbers()
    -- Test large token counts (near Number.MAX_SAFE_INTEGER)
    local large = 9007199254740991 -- Number.MAX_SAFE_INTEGER
    local snap = {
        version = 1,
        timestamp = 1692000000000,
        agent = "opencode",
        tokens_today = large,
        tokens_by_model = { ["gpt-4o"] = large },
    }

    local json_str = noctalia.json.encode(snap)
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true)
    assert_equal(decoded.tokens_today, large)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Run All Tests
-- ─────────────────────────────────────────────────────────────────────────────

local tests = {
    { "Basic snapshot round-trip", test_basic_snapshot },
    { "All agents round-trip", test_all_agents },
    { "Minimal snapshot", test_optional_fields },
    { "Nested objects", test_nested_objects },
    { "Special values (null/empty)", test_special_values },
    { "Timestamp precision", test_timestamp_precision },
    { "Unicode support", test_unicode },
    { "Large numbers", test_large_numbers },
}

local passed = 0
local failed = 0

print("=== Running Protocol Round-trip Tests ===\n")

for _, test in ipairs(tests) do
    local name, fn = test[1], test[2]
    local ok, err = pcall(fn)
    if ok then
        print("✓ " .. name)
        passed = passed + 1
    else
        print("✗ " .. name .. ": " .. tostring(err))
        failed = failed + 1
    end
end

print("\n=== Results: " .. passed .. " passed, " .. failed .. " failed ===")

if failed > 0 then
    os.exit(1)
end

print("✓ All protocol round-trip tests passed!")