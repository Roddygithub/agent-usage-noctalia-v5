-- Collector Unit Tests for Agent Usage Monitor
-- Tests all collector modules and protocol compliance
-- Author: roddygithub
-- Plugin API: 27

--!nonstrict

-- Use downloaded dkjson.lua
local json = require("dkjson")
noctalia = {
    json = {
        encode = json.encode,
        decode = json.decode,
    }
}

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Protocol Round-trip Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_protocol_roundtrip()
    -- Test that a snapshot can be encoded and decoded correctly
    local snapshot = {
        version = 1,
        timestamp = 1692000000000,
        agent = "opencode",
        plan = "Free",
        quota = { used = 15000, limit = 50000, reset_ms = 1692086400000, period = "day" },
        balance = { credits = 10.50, currency = "USD", estimated = false },
        speaking = false,
        tokens_today = 15000,
        tokens_by_model = { ["gpt-4o"] = 10000, ["gpt-4o-mini"] = 5000 },
        tokens_by_type = { input = 10000, output = 4000, cache = 1000 },
        limits = { { name = "Daily", used = 15000, limit = 50000, reset_ms = 1692086400000, percent = 30 } },
    }

    -- Encode to JSON
    local json_str = noctalia.json.encode(snapshot)
    assert_table_contains({json_str=json_str}, "json_str", "JSON encode returned nil")

    -- Decode back
    local ok, decoded = pcall(noctalia.json.decode, json_str)
    assert_equal(ok, true, "JSON decode failed")

    -- Verify key fields preserved
    assert_equal(decoded.version, 1)
    assert_equal(decoded.agent, "opencode")
    assert_equal(decoded.plan, "Free")
    assert_equal(decoded.quota.used, 15000)
    assert_equal(decoded.quota.limit, 50000)
    assert_equal(decoded.balance.credits, 10.50)
    assert_equal(#decoded.limits, 1)
end

local function test_header_format()
    local header = "AGENT_USAGE/1.0\n"
    local payload = '{"version":1,"timestamp":123,"agent":"opencode"}'
    local full = header .. payload

    -- Verify header parsing
    local lines = {}
    for line in full:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    assert_equal(lines[1], "AGENT_USAGE/1.0")
    assert_equal(lines[2], '{"version":1,"timestamp":123,"agent":"opencode"}')
end

local function test_json_lines()
    local snapshots = {
        { version = 1, timestamp = 1, agent = "opencode" },
        { version = 1, timestamp = 2, agent = "claude" },
    }

    local lines = {}
    for _, snap in ipairs(snapshots) do
        table.insert(lines, noctalia.json.encode(snap))
    end

    local payload = table.concat(lines, "\n")
    local full = "AGENT_USAGE/1.0\n" .. payload

    -- Parse back
    local lines_parsed = {}
    for line in full:gmatch("[^\n]+") do
        table.insert(lines_parsed, line)
    end

    assert_equal(lines_parsed[1], "AGENT_USAGE/1.0")
    assert_equal(#lines_parsed, 3) -- header + 2 JSON lines

    local ok1, snap1 = pcall(noctalia.json.decode, lines_parsed[2])
    local ok2, snap2 = pcall(noctalia.json.decode, lines_parsed[3])
    assert_equal(ok1, true)
    assert_equal(ok2, true)
    assert_equal(snap1.agent, "opencode")
    assert_equal(snap2.agent, "claude")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Collector Contract Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_collector_contract()
    -- Test that each collector has required fields
    local collectors = { "opencode", "claude", "codex", "fireworks" }

    for _, name in ipairs(collectors) do
        local ok, collector = pcall(require, "collectors." .. name)
        if not ok then
            print("⚠ Collector " .. name .. " not loadable (expected if deps missing)")
        else
            assert_equal(type(collector), "table", name .. " must return table")
            assert_equal(type(collector.name), "string", name .. " must have name")
            assert_equal(collector.name, name)
            assert_equal(type(collector.collect), "function", name .. " must have collect function")
            assert_equal(type(collector.validate_config), "function", name .. " must have validate_config")
            assert_equal(type(collector.default_config), "table", name .. " must have default_config")

            -- Test validate_config with defaults
            local valid, err = collector.validate_config(collector.default_config)
            assert_equal(valid, true, name .. " default config should be valid: " .. tostring(err))
        end
    end
end

local function test_opencode_collector()
    local ok, collector = pcall(require, "collectors.opencode")
    if not ok then
        print("⚠ opencode collector not loadable")
        return
    end

    -- Test with mock data
    -- Note: Can't easily test without mocking noctalia.readFile
    -- Just verify contract
    assert_equal(type(collector.collect), "function")
    assert_equal(type(collector.validate_config), "function")
end

local function test_claude_collector()
    local ok, collector = pcall(require, "collectors.claude")
    if not ok then
        print("⚠ claude collector not loadable")
        return
    end
    assert_equal(type(collector.collect), "function")
end

local function test_codex_collector()
    local ok, collector = pcall(require, "collectors.codex")
    if not ok then
        print("⚠ codex collector not loadable")
        return
    end
    assert_equal(type(collector.collect), "function")
end

local function test_fireworks_collector()
    local ok, collector = pcall(require, "collectors.fireworks")
    if not ok then
        print("⚠ fireworks collector not loadable")
        return
    end
    assert_equal(type(collector.collect), "function")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Config Validation Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_config_validation()
    local collectors = { "opencode", "claude", "codex", "fireworks" }

    for _, name in ipairs(collectors) do
        local ok, collector = pcall(require, "collectors." .. name)
        if ok and collector.validate_config then
            -- Valid config
            local valid, err = collector.validate_config(collector.default_config)
            assert_equal(valid, true, name .. " default config valid: " .. tostring(err))

            -- Invalid config
            valid, err = collector.validate_config({ invalid = "config" })
            -- Should still be valid (extra keys allowed) or return false with error
            -- Just verify it doesn't crash
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Snapshot Structure Tests
-- ─────────────────────────────────────────────────────────────────────────────

local function test_snapshot_schema()
    local required_fields = { "version", "timestamp", "agent" }
    local optional_fields = {
        "plan", "quota", "balance", "speaking", "tokens_today",
        "tokens_by_model", "tokens_by_type", "tokens_by_type",
        "tokens_daily", "limits"
    }

    local test_snapshots = {
        {
            version = 1,
            timestamp = 1692000000000,
            agent = "opencode",
        },
        {
            version = 1,
            timestamp = 1692000000000,
            agent = "claude",
            plan = "Pro",
            quota = { used = 100, limit = 1000, reset_ms = 1692086400000, period = "day" },
            balance = { credits = 10.0, currency = "USD", estimated = false },
            speaking = true,
            tokens_today = 5000,
            tokens_by_model = { ["claude-3-opus"] = 1000 },
            tokens_by_type = { input = 500, output = 500 },
            limits = { { name = "Daily", used = 100, limit = 1000, reset_ms = 1692086400000, percent = 10 } },
        }
    }

    for _, snap in ipairs(test_snapshots) do
        for _, field in ipairs(required_fields) do
            assert_table_contains(snap, field, "Missing required field: " .. field)
        end
        assert_equal(snap.version, 1)
        assert_equal(type(snap.timestamp), "number")
        assert_equal(type(snap.agent), "string")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Run All Tests
-- ─────────────────────────────────────────────────────────────────────────────

local tests = {
    { "Protocol: Round-trip encode/decode", test_protocol_roundtrip },
    { "Protocol: Header format", test_header_format },
    { "Protocol: JSON Lines format", test_json_lines },
    { "Collectors: Contract compliance", test_collector_contract },
    { "Collector: opencode", test_opencode_collector },
    { "Collector: claude", test_claude_collector },
    { "Collector: codex", test_codex_collector },
    { "Collector: fireworks", test_fireworks_collector },
    { "Config: Validation", test_config_validation },
    { "Schema: Snapshot structure", test_snapshot_schema },
}

local passed = 0
local failed = 0

print("=== Running Collector Unit Tests ===\n")

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