# Agent Usage Monitor for Noctalia V5

Native Noctalia V5 plugin that monitors AI coding agent usage (Claude, Codex, opencode, Fireworks, OpenRouter, OpenCode Zen) and displays real-time quota, balance, and token analytics in your bar and panel.

## Features

- **Multi-agent support**: Claude (Anthropic), Codex (OpenAI), opencode, Fireworks, OpenRouter, OpenCode Zen
- **Real-time bar widget**: Glyph + quota percentage + speaking indicator
- **Detailed panel**: Limits, balance, tokens/day, tokens/model, history
- **Multi-machine sync**: Optional sync via Syncthing/Dropbox/rsync
- **Zero token exposure**: Reads local usage files only, never touches API keys
- **Native Noctalia V5**: Luau, layer-shell, declarative UI, shared state
- **Persistent state cache**: Instant startup with last known state
- **Graceful degradation**: Missing agents/APIs handled silently

## Architecture

```
┌─────────────────┐     noctalia.state      ┌──────────────────┐
│  Collector      │ ─────────────────────►  │  Widget Barre    │
│  (service.luau) │   shared state          │  (bar_widget)    │
└─────────────────┘                         └────────┬─────────┘
                                                     │
┌─────────────────┐                                 ▼
│  Panel.luau     │ ◄──── watch("agent_usage") ── ┌──────────────────┐
│  (UI détaillée) │                                │  Shortcut CC     │
└─────────────────┘                                └──────────────────┘
```

**Collectors** (run inside service):
- `opencode` → `~/.config/opencode/usage.json`
- `claude` → `~/.claude/stats-cache.json` + `history.jsonl` + OAuth API
- `codex` → `~/.codex/sessions/` + app-server RPC
- `fireworks` → Billing API + `~/.config/agent-usage/fireworks.json`
- `openrouter` → OpenRouter API (`/auth/key` + `/models`) — reads key from `~/.local/share/opencode/auth.json`
- `opencode-zen` → Detects free models via `~/.local/share/opencode/auth.json` (DeepSeek V4 Flash Free, MiMo, Nemotron, etc.)

## Installation

### Development (Local Source)

```bash
# Clone
git clone https://github.com/Roddygithub/agent-usage-noctalia-v5.git
cd agent-usage-noctalia-v5

# Install BMAD + Superpowers + Vibe Coding tooling
./scripts/bootstrap-bmad.sh
./scripts/bootstrap-superpowers.sh
./scripts/bootstrap-vibe-coding.sh

# Link as local Noctalia plugin source
mkdir -p ~/.local/share/noctalia/plugins
ln -s $(pwd) ~/.local/share/noctalia/plugins/agent-usage

# Enable via Noctalia IPC
noctalia msg plugins enable roddygithub/agent-usage
```

### From Noctalia Community Plugins

Once published to `noctalia-dev/community-plugins`:
1. Settings → Plugins → Ensure `community` source enabled
2. Search "Agent Usage" → Enable

### Install Release Artifact

Download from [Releases](https://github.com/Roddygithub/agent-usage-noctalia-v5/releases):
```bash
tar -xzf agent-usage-noctalia-v5-plugin-1.0.0.tar.gz
mkdir -p ~/.local/share/noctalia/plugins
mv agent-usage-noctalia-v5 ~/.local/share/noctalia/plugins/agent-usage
noctalia msg plugins enable roddygithub/agent-usage
```

## Usage

### Bar Widget
- **Left click**: Toggle panel
- **Right click**: Force refresh
- **Tooltip**: Detailed quota, balance, speaking status
- **Speaking pulse**: Animated glyph when agent is processing

### Panel (Ctrl+Alt+A or bar click)
- **Hero**: Active agent + plan + auth status
- **Limits**: % used, meter, reset timer
- **Balance**: Fuel gauge (Fireworks) or credit ledger
- **Tokens/Day**: 7-day chart, today bold
- **Tokens/Model**: Breakdown with input/output/cache split
- **Sync status**: Multi-machine aggregation status

### Shortcut (Control Center)
- Quick toggle panel
- Shows active agent badge

### Keybinds
- `Ctrl+Alt+A` → Toggle panel
- `Ctrl+Alt+R` → Force refresh

## Configuration

All settings in Noctalia Settings → Plugins → Agent Usage (gear icon):

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `refresh_interval_sec` | int | 300 | Collector refresh interval |
| `enabled_agents` | list | ["opencode","claude","codex","fireworks","opencode-zen","openrouter"] | Which agents to track |
| `sync_mode` | enum | "Off" | "Off" / "On" (multi-machine) |
| `sync_dir` | path | "" | Syncthing/Dropbox/rsync folder |
| `sync_device_id` | string | hostname | Stable device name |
| `show_speaking_indicator` | bool | true | Pulse animation when agent active |

### Widget Settings (per-instance)
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `glyph_opencode` | glyph | "code" | Glyph for opencode |
| `glyph_claude` | glyph | "bot" | Glyph for Claude |
| `glyph_codex` | glyph | "terminal" | Glyph for Codex |
| `glyph_fireworks` | glyph | "flame" | Glyph for Fireworks |
| `glyph_opencode_zen` | glyph | "sparkles" | Glyph for OpenCode Zen |
| `glyph_openrouter` | glyph | "route" | Glyph for OpenRouter |
| `hide_when_idle` | bool | false | Hide widget when no agents active |

## Development

### Methodology Stack

This project uses a **hybrid methodology** combining the best of:

| Methodology | Role |
|-------------|------|
| **BMAD** | Memory bank, agents, workflows, durable context |
| **Superpowers** | TDD skill, subagent-driven-dev, systematic debugging, git worktrees |
| **Spec Kit** | Protocol spec-first (OpenSpec format for Unix socket v1) |
| **Vibe Coding** | Memory-bank discipline, step-by-step implementation with test validation |

### Memory Bank

Durable project context lives in `memory-bank/`:

```
memory-bank/
├── prd.md              # Product Requirements Document
├── spec.md             # Protocol spec (OpenSpec format)
├── tech-stack.md       # Technology choices & justification
├── architecture.md     # System architecture & data flows
├── implementation-plan.md  # Step-by-step tasks with tests
└── progress.md         # Completed work journal
```

**Always read before coding**: `prd.md`, `spec.md`, `tech-stack.md`, `implementation-plan.md`

### Bootstrap

```bash
# BMAD Method (agents, workflows, memory bank)
./scripts/bootstrap-bmad.sh

# Superpowers skills (TDD, subagent-driven-dev, debugging)
./scripts/bootstrap-superpowers.sh

# Vibe Coding guide (Nicolas Zullo / EnzeD)
./scripts/bootstrap-vibe-coding.sh
```

### Protocol Spec

The Unix socket protocol is defined in OpenSpec format at `specs/protocol-v1.openspec.yaml` (or `.json`). This is the **single source of truth** for the collector ↔ widget communication.

### Collector Development

Each agent has a dedicated collector in `collectors/`:

```
collectors/
├── opencode.lua      # Reads ~/.config/opencode/usage.json
├── claude.lua        # Reads ~/.claude/stats-cache.json + OAuth
├── codex.lua         # Reads ~/.codex/sessions/ + RPC
├── fireworks.lua     # Billing API + config
├── openrouter.lua    # OpenRouter API (credits, free models)
└── opencode-zen.lua  # Detection only (no API tracking)
```

Collectors are loaded by `service.luau` and run on the configured refresh interval.

### Testing

```bash
# Luau lint
luau-lsp --check .

# Protocol round-trip test
cd specs && lua test_protocol_roundtrip.lua

# Collector unit tests
lua collectors/test_collectors.lua

# Full integration test (requires Noctalia running)
./scripts/test_integration.sh
```

## Protocol Specification (v1)

The Unix socket uses a simple line-delimited JSON protocol:

```
Header: AGENT_USAGE/1.0\n
Payload: JSON Lines (one snapshot per line)
```

**Snapshot Schema**:
```json
{
  "version": 1,
  "timestamp": 1692000000000,
  "agent": "opencode",
  "plan": "Free",
  "quota": { "used": 15000, "limit": 50000, "reset_ms": 1692086400000 },
  "balance": { "credits": 10.50, "currency": "USD" },
  "speaking": false,
  "tokens_today": 45000,
  "tokens_by_model": { "gpt-4o": 30000, "gpt-4o-mini": 15000 }
}
```

## Release v1.0.0

**Published**: 2026-08-15

Artifacts:
- `agent-usage-noctalia-v5-plugin-1.0.0.tar.gz` — Noctalia plugin package
- `agent-usage-noctalia-v5-v1.0.0.tar.gz` — Full source archive

[View Release](https://github.com/Roddygithub/agent-usage-noctalia-v5/releases/tag/v1.0.0)

## Distribution

- **Source**: GitHub (this repo)
- **Installation**: Noctalia plugin system (git source or artifact)
- **Updates**: `noctalia msg plugins update <source>`

## License

GPL-3.0 — see `LICENSE`.

## Upstream

- [Noctalia](https://github.com/noctalia-dev/noctalia) — Desktop shell (MIT)
- [opencode](https://github.com/sst/opencode) — AI coding agent
- [Claude](https://anthropic.com) — Anthropic AI
- [Codex](https://openai.com/codex) — OpenAI agent
- [Fireworks](https://fireworks.ai) — Inference platform
- [OpenRouter](https://openrouter.ai) — Multi-provider gateway