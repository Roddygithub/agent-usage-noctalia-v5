#!/bin/bash
set -euo pipefail

# Integration test script for Agent Usage Monitor
# Requires: Noctalia running, plugin installed locally

echo "=== Agent Usage Monitor Integration Test ==="

# Check if Noctalia is running
if ! pgrep -x "noctalia" >/dev/null; then
    echo "ERROR: Noctalia not running. Start Noctalia first."
    exit 1
fi

echo "✓ Noctalia is running"

# Check if plugin is enabled
if ! noctalia msg plugins list | grep -q "roddygithub/agent-usage"; then
    echo "ERROR: Plugin not enabled. Run: noctalia msg plugins enable roddygithub/agent-usage"
    exit 1
fi

echo "✓ Plugin is enabled"

# Test 1: Service status
echo "Test 1: Checking service status..."
if ! noctalia msg plugin roddygithub/agent-usage:service all refresh; then
    echo "FAIL: Service refresh command failed"
    exit 1
fi
echo "✓ Service refresh works"

# Wait for collection
sleep 2

# Test 2: Check state published
echo "Test 2: Checking shared state..."
sleep 1
# This would need a way to read state from Noctalia
# For now, just check logs
if journalctl --user -u noctalia --since "10 seconds ago" | grep -q "\[agent-usage\]"; then
    echo "✓ Service logging detected"
else
    echo "WARN: No agent-usage logs found"
fi

# Test 3: Panel toggle
echo "Test 3: Testing panel toggle..."
if ! noctalia msg panel-toggle roddygithub/agent-usage:detail; then
    echo "FAIL: Panel toggle failed"
    exit 1
fi
echo "✓ Panel toggle works"

# Test 4: Protocol round-trip
echo "Test 4: Testing protocol round-trip..."
if lua specs/test_protocol_roundtrip.lua; then
    echo "✓ Protocol round-trip test passed"
else
    echo "FAIL: Protocol round-trip test failed"
    exit 1
fi

# Test 5: Collector unit tests
echo "Test 5: Running collector unit tests..."
if lua collectors/test_collectors.lua; then
    echo "✓ Collector unit tests passed"
else
    echo "FAIL: Collector unit tests failed"
    exit 1
fi

echo ""
echo "=== All integration tests passed! ==="