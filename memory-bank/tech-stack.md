# Tech Stack — Agent Usage Monitor for Noctalia V5

## 1. Runtime & Langage

| Composant | Version / Détail | Justification |
|-----------|------------------|---------------|
| **Luau** | Embedded dans Noctalia (vendor `third_party/luau`) | VM isolée, JIT, sandboxing, types optionnels (`--!nonstrict`) |
| **Plugin API** | `27` (current Noctalia v5 beta) | Accès complet : `panel`, `service`, `shortcut`, `noctalia.state`, `runAsync`, `getSetting`, `pluginDataDir` |
| **Noctalia** | v5 Beta (nightly ou ≥ 0.5.x) | Shell cible, layer-shell, IPC, plugin system |

## 2. Dépendances Système (Arch Linux)

```bash
# Runtime Noctalia (déjà installé)
# Voir https://docs.noctalia.dev/noctalia/getting-started/installation/

# Outils optionnels pour collectors
sudo pacman -S curl jq  # Pour API calls si pas de Luau HTTP natif

# Noctalia (déjà installé sur la machine cible)
# Voir https://docs.noctalia.dev/noctalia/getting-started/installation/
```

## 3. Sources de Données (Collectors)

| Agent | Source Principale | API Optionnelle | Fichiers Locaux |
|-------|-------------------|-----------------|-----------------|
| **opencode** | `~/.config/opencode/usage.json` | — | JSON natif |
| **claude** | `~/.claude/stats-cache.json` + `history.jsonl` | Anthropic OAuth (5h session + 7j weekly) | JSON + JSONL |
| **codex** | `~/.codex/sessions/` | App-server RPC | Fichiers session natifs |
| **fireworks** | `~/.config/agent-usage/fireworks.json` | Fireworks Billing API | JSON + API REST |

## 4. Architecture Plugin Noctalia

```
agent-usage-noctalia-v5/
├── plugin.toml                      # Manifest : id, name, version, plugin_api=27, entries[], settings[][]
├── service.luau                     # [[service]] id="collector" — singleton, poll collectors, publish state
├── bar_widget.luau                  # [[widget]] id="status" — render glyph+quota%, onClick/onRightClick
├── panel.luau                       # [[panel]] id="detail" — ui.* tree, watch state, actions → IPC
├── shortcut.luau                    # [[shortcut]] id="toggle" — Control Center tile, state watch
├── collectors/                      # Modules Lua purs (un par agent)
│   ├── opencode.lua
│   ├── claude.lua
│   ├── codex.lua
│   └── fireworks.lua
├── specs/
│   └── protocol-v1.openspec.yaml    # Spec OpenSpec v3.0.3 (single source of truth)
├── translations/
│   └── en.json                      # Clés i18n
├── scripts/
│   ├── bootstrap-bmad.sh
│   ├── bootstrap-superpowers.sh
│   ├── bootstrap-vibe-coding.sh
│   └── test_integration.sh
├── memory-bank/                     # BMAD durable context
│   ├── prd.md
│   ├── spec.md (→ specs/protocol-v1.openspec.yaml)
│   ├── tech-stack.md
│   ├── architecture.md
│   ├── implementation-plan.md
│   └── progress.md
├── .opencode/
│   └── skills/                      # Superpowers skills (TDD, debugging, etc.)
├── .github/workflows/
│   ├── ci.yml
│   └── release.yml
└── README.md
```

### Communication Inter-Entrées

```
┌─────────────────┐     noctalia.state.set/get/watch      ┌──────────────────┐
│  service.luau   │ ─────────────────────────────────────► │  bar_widget.luau │
│  (singleton)    │ ◄───────────────────────────────────── │  (watch "agent_usage")│
└────────┬────────┘                                        └──────────────────┘
         │                                                         │
         │ IPC (noctalia.msg.plugin)                               │ onClick
         ▼                                                         ▼
┌─────────────────┐                                        ┌──────────────────┐
│  panel.luau     │ ◄──── watch("agent_usage") ──────────── │  shortcut.luau   │
│  (ui.render)    │                                         │  (watch + IPC)   │
└─────────────────┘                                        └──────────────────┘
```

**Clés d'état partagé** (`noctalia.state`):
| Clé | Type | Producteur | Consommateurs |
|-----|------|------------|---------------|
| `agent_usage` | table | service | widget, panel, shortcut |
| `agent_usage_speaking` | bool | service | widget (speaking pulse) |
| `agent_usage_sync` | table | service | panel (sync status) |

## 5. API Noctalia Utilisées (plugin_api ≥ requis)

| Fonction | API min | Usage |
|----------|---------|-------|
| `noctalia.state.set/get/watch` | 3 | Partage état core |
| `noctalia.runAsync(argv, cb)` | 24 | Appels HTTP/API sécurisés (argv array) |
| `noctalia.getConfig(key)` | 3 | Lecture settings plugin |
| `noctalia.pluginDataDir()` | 3 | Persistance cross-restart |
| `noctalia.log(msg)` | 3 | Debug avec préfixe `[agent-usage]` |
| `noctalia.notify(title, body)` | 3 | Notifications erreurs/user |
| `barWidget.setText/setGlyph/render` | 3/21 | Widget rendu impératif/déclaratif |
| `panel.render(ui_tree)` | 5 | Panel UI déclaratif |
| `shortcut.setActive(bool)` | 5 | Shortcut état visuel |
| `noctalia.getSetting(path)` | 26 | Lecture config shell effective |
| `noctalia.setTimeout/clearTimeout` | 3 | Timers debounce, retry |
| `noctalia.setUpdateInterval(ms)` | 3 | Intervalle poll service |
| `noctalia.formatTime(pattern, ts?)` | 19 | Formatage timestamps |
| `noctalia.isDarkMode()` | 3 | Thème adaptatif badges |
| `noctalia.tr(key, subst)` | 3 | i18n |
| `noctalia.json.encode/decode` | 3 | Persistance JSON |

## 6. Outils Développement

| Outil | Usage |
|-------|-------|
| **luau-lsp** | LSP pour VS Code / Neovim — autocomplete `noctalia.*`, `barWidget.*`, `panel.*`, `ui.*` |
| `noctalia.d.luau` | Definitions types (dans `official-plugins/`) — copier dans plugin ou configurer lsp |
| `noctalia msg plugins enable ...` | Test activation plugin local |
| `noctalia msg plugin author/plugin:entry all <ipc>` | Test IPC manuel |
| `journalctl --user -f -u noctalia` | Logs Noctalia + `noctalia.log()` |
| `luau-lsp --check .` | Luau lint |

## 7. Configuration Développement Local

```bash
# 1. Clone repo plugin en local source
mkdir -p ~/.local/share/noctalia/plugins
ln -s ~/Projets/agent-usage-noctalia-v5 ~/.local/share/noctalia/plugins/agent-usage

# 2. Activer via IPC
noctalia msg plugins enable roddygithub/agent-usage

# 3. Logs en temps réel
journalctl --user -f -u noctalia | grep -E "\[agent-usage\]"

# 4. Recharger script après édition (auto via file watcher Noctalia)
noctalia msg plugins disable roddygithub/agent-usage && \
noctalia msg plugins enable roddygithub/agent-usage
```

## 8. CI / Quality Gates

| Check | Tool | Command |
|-------|------|---------|
| **Luau lint** | luau-lsp | `luau-lsp --check .` |
| **Protocol round-trip** | Custom | `lua specs/test_protocol_roundtrip.lua` |
| **Collector unit tests** | Luau | `lua collectors/test_collectors.lua` |
| **Luau format** | stylua | `stylua .` |

## 9. Publication (Workflow)

1. Développement local → `~/.local/share/noctalia/plugins/`
2. Tests manuels complets (widget, panel, shortcut, settings, restart)
3. Push vers fork GitHub `roddygithub/agent-usage-noctalia-v5`
4. PR vers `noctalia-dev/community-plugins` (suivre leur template)
5. Review + merge → dispo dans source `community` pour tous

## 10. Versions & Compatibilité

| Composant | Version Min | Version Testée | Notes |
|-----------|-------------|----------------|-------|
| Noctalia | v5 beta (API 3) | API 27 (current) | Cibler 27, fallback graceful si < 27 |
| opencode | Latest | Latest | `~/.config/opencode/usage.json` |
| Claude Code | Latest | Latest | OAuth + `~/.claude/` |
| Codex CLI | Latest | Latest | `~/.codex/` + RPC |
| Fireworks | API v1 | Latest | Billing API + config |
| Luau | Vendor Noctalia | - | Pas de version indépendante |
| Arch Linux | Rolling | Current | Dépendances standards |