# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project structure with BMAD, Superpowers, Vibe Coding methodology
- Protocol specification v1 in OpenSpec format (`specs/protocol-v1.openspec.yaml`)
- Protocol round-trip tests (`specs/test_protocol_roundtrip.lua`)
- Collector modules for all 4 agents:
  - `collectors/opencode.lua` - Reads `~/.config/opencode/usage.json`
  - `collectors/claude.lua` - Reads `~/.claude/stats-cache.json` + `history.jsonl` + OAuth
  - `collectors/codex.lua` - Reads `~/.codex/sessions/` + RPC
  - `collectors/fireworks.lua` - Billing API + local config
- Collector unit tests (`collectors/test_collectors.lua`)
- Service (`service.luau`) with:
  - Collector loading and validation
  - Poll loop with retry logic
  - IPC command handling (refresh, toggle_sync, force_sync)
  - Sync writing for multi-machine
  - Speaking pulse management
- Bar widget (`bar_widget.luau`) with:
  - Glyph + quota display
  - Speaking pulse animation
  - Hide when idle option
  - Tooltip with detailed info
  - Click/right-click handlers
- Detail panel (`panel.luau`) with declarative UI:
  - Hero section with agent badge, plan, auth status
  - Limits accordion with progress bars
  - Balance gauge (Fuel gauge for Fireworks)
  - Tokens/Day (7-day chart)
  - Tokens/Model breakdown with input/output/cache split
  - Sync status section
- Control Center shortcut (`shortcut.luau`)
- Plugin manifest (`plugin.toml`) with:
  - Service, widget, panel, shortcut entries
  - Plugin-level settings (refresh_interval, enabled_agents, sync_mode, sync_dir, sync_device_id, show_speaking_indicator)
  - Widget settings (glyphs, hide_when_idle)
  - Keybinds (Ctrl+Alt+A, Ctrl+Alt+R)
- Translations (`translations/en.json`)
- CI/CD workflow (`.github/workflows/ci.yml`) with luau-lsp, protocol tests, collector tests, stylua
- Bootstrap scripts for BMAD, Superpowers, Vibe Coding
- Integration test script (`scripts/test_integration.sh`)
- Memory bank with PRD, Spec, Tech Stack, Architecture, Implementation Plan, Progress

### Fixed
- Timestamp calculation bug (was using `os.clock()` incorrectly, now uses `os.time() * 1000`)
- Missing `format_time_ms` function references in panel.luau (was using undefined `format_time`)

## [0.1.0] - 2026-08-15

### Added
- Initial release candidate with all core features implemented