# Agent Usage Monitor — Engineering Constraints

## Mission

Build a reliable, privacy-respecting agent usage monitor for Noctalia V5 that displays real-time quota, balance, and token analytics for AI coding agents (opencode, Claude, Codex, Fireworks) without ever accessing or transmitting API keys.

## Architecture

- **Collector Service** (Luau): Polls local usage files + OAuth APIs, publishes normalized snapshots to `noctalia.state`
- **Bar Widget** (Luau): Watches `agent_usage` state, renders glyph + quota %, handles click/right-click
- **Panel** (Luau): Declarative UI via `panel.render()`, watches state, renders limits/balance/tokens charts
- **Shortcut** (Luau): Control Center tile, toggles panel
- **Collectors** (Lua modules): Per-agent data extraction, isolated, testable

## Security Boundaries

- **Never** read, log, persist, or transmit API keys / tokens / secrets
- **Never** connect to Discord Gateway or any external service not explicitly configured
- **Only** read local files: `~/.config/opencode/`, `~/.claude/`, `~/.codex/`, `~/.config/agent-usage/`
- **Only** call OAuth APIs with user-granted tokens (Claude, Codex, Fireworks)
- Restrict local IPC to current user via `noctalia.state` (in-memory, user-scoped)
- Do not commit credentials, usage data, or personal logs

## Quality

- **Protocol first**: Unix socket protocol v1 defined in OpenSpec (`specs/protocol-v1.openspec.yaml`)
- **TDD enforced**: Every collector has unit tests; protocol round-trip tested
- **Superpowers skills**: `test-driven-development`, `systematic-debugging`, `subagent-driven-development`
- **Memory bank discipline**: Read `memory-bank/` before coding; update `progress.md` + `architecture.md` after each step
- **Collector isolation**: Each collector is a pure Lua module, no shared mutable state
- **Graceful degradation**: Missing agent → disabled silently; API failure → cached data + warning

## Licensing

- Repository: GPL-3.0 (compatible with Noctalia MIT, opencode MIT, Discover GPL-3.0)
- Preserve upstream notices; record exact upstream repo/revision for adapted code

## Tooling

- **BMAD Method**: Memory bank, agents, workflows (`./scripts/bootstrap-bmad.sh`)
- **Superpowers**: Skills (TDD, subagent-driven-dev, debugging) (`./scripts/bootstrap-superpowers.sh`)
- **Vibe Coding**: Guide by Nicolas Zullo (`./scripts/bootstrap-vibe-coding.sh`)
- **Spec Kit**: Protocol spec in OpenSpec format (`specs/protocol-v1.openspec.yaml`)

## Development Rules

1. **Always read** `memory-bank/{prd.md,spec.md,tech-stack.md,implementation-plan.md}` before writing code
2. **Write tests first** (TDD) — collector unit tests + protocol round-trip
3. **Use Superpowers skills**: `test-driven-development`, `systematic-debugging`, `subagent-driven-development`
4. **Update memory bank** after each validated step: `progress.md` + `architecture.md`
5. **Collector isolation**: Pure functions, no side effects, single responsibility
6. **Protocol compliance**: All collectors emit v1 schema; round-trip test in CI

## Git Workflow

- Atomic commits, one coherent change
- Conventional Commits + DCO sign-off (`git commit -s`)
- Feature branches → PR → squash merge to `main`

## Collector Contract

Each collector in `collectors/<agent>.lua` exports:

```lua
return {
  name = "opencode",                    -- agent identifier
  collect = function(config) -> snapshot_or_nil, err  -- pure function
  validate_config = function(config) -> bool, err     -- config validation
  default_config = { ... }              -- defaults for plugin.toml
}
```

## Testing Requirements

- Collector unit tests: `collectors/test_<agent>.lua`
- Protocol round-trip: `specs/test_protocol_roundtrip.lua`
- Integration: `scripts/test_integration.sh` (requires Noctalia running)
- Luau lint: `luau-lsp --check .`

## Deployment

- Noctalia plugin system: git source → `noctalia msg plugins enable`
- Versioning: Git tags `vX.Y.Z` = protocol + plugin + collectors compatible
- Protocol version in header: `AGENT_USAGE/1.0`