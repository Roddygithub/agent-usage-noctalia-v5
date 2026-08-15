# Architecture — Agent Usage Monitor for Noctalia V5

## 1. Vue d'Ensemble Système

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           NOCTALIA SHELL (v5)                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Bar        │  │ Control Ctr  │  │  Launcher    │  │  Panels      │   │
│  │  (widgets)   │  │ (shortcuts)  │  │ (providers)  │  │  (ui.render) │   │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘   │
│         │                 │                 │                 │            │
│         └─────────────────┼─────────────────┼─────────────────┘            │
│                           ▼                                                 │
│              ┌────────────────────────┐                                    │
│              │   Plugin Runtime       │                                    │
│              │   (Luau VMs isolées)   │                                    │
│              │  ┌──────────────────┐  │                                    │
│              │  │  Shared State    │  │  ← noctalia.state (in-memory)     │
│              │  │  (agent_usage)   │  │                                    │
│              │  └──────────────────┘  │                                    │
│              └───────────┬────────────┘                                    │
└──────────────────────────┼────────────────────────────────────────────────┘
                           │ IPC (noctalia.msg.plugin)
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AGENT USAGE PLUGIN ENTRIES                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │  service    │  │ bar_widget  │  │   panel     │  │  shortcut   │       │
│  │  (singleton)│  │  (widget)   │  │  (ui.tree)  │  │  (tile)     │       │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │
│         │                │                │                │              │
│         └────────────────┼────────────────┼────────────────┘              │
│                          ▼                                                │
│               ┌─────────────────────┐                                     │
│               │   COLLECTORS        │                                     │
│               │  (Lua modules)      │                                     │
│               │  opencode.lua       │                                     │
│               │  claude.lua         │                                     │
│               │  codex.lua          │                                     │
│               │  fireworks.lua      │                                     │
│               └─────────────────────┘                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2. Composants Détaillés

### 2.1 Service (`service.luau`) — Cœur du Plugin

**Responsabilités** :
- Chargement dynamique des collectors activés (`collectors/<agent>.lua`)
- Poll périodique (configurable, défaut 300s) de tous les collectors
- Normalisation → snapshot v1 (schema `specs/protocol-v1.openspec.yaml`)
- Publication `noctalia.state.set("agent_usage", snapshot)` pour widget/panel/shortcut
- Gestion IPC : `refresh` (force collect), `toggle_sync` (multi-machine)
- Gestion erreurs robuste : try/catch par collector, fallback cache, degraded mode
- Speaking detection : `speaking` flag dans snapshot → widget pulse

**État Interne** :
```lua
local state = {
  collectors = {},           -- { name = collector_module }
  config = {},               -- plugin settings
  cache = {},                -- { agent = last_snapshot }
  poll_timer = nil,
  speaking_timer = nil,      -- pulse animation timer
}
```

**Cycle de Vie** :
```
init()
  → load_config()
  → load_collectors()        -- require collectors/<agent>.lua
  → validate_collectors()    -- check validate_config()
  → setup_poll(config.refresh_interval_sec)
  → state.set("agent_usage", initial_snapshot)
  → log("started")

update() -- appelé par Noctalia selon setUpdateInterval
  → for each collector: runAsync(collect, callback)
  → callback: merge snapshots → publish_status()

onIpc(payload)
  → match payload.cmd
  → if "refresh": force_collect()
  → if "toggle_sync": toggle_sync_mode()

shutdown()
  → clear poll timer
  → state.set("agent_usage", {state="stopped"})
```

### 2.2 Collectors (`collectors/<agent>.lua`) — Modules Purs

**Contract Standard** :
```lua
return {
  name = "opencode",
  default_config = { enabled = true, config_path = "~/.config/opencode/usage.json" },
  validate_config = function(cfg) return true/false, err end,
  collect = function(config)
    -- Returns: snapshot_table|nil, error
    -- snapshot = { agent="opencode", plan="Free", quota={used,limit,reset_ms}, ... }
  end
}
```

**Détails par Agent** :

| Agent | Source | Méthode | Fallback |
|-------|--------|---------|----------|
| **opencode** | `~/.config/opencode/usage.json` | `noctalia.readFile` + `json.decode` | Disabled si fichier absent |
| **claude** | `~/.claude/stats-cache.json` + `history.jsonl` | JSON parse + OAuth API (optionnel) | Cache local si API fail |
| **codex** | `~/.codex/sessions/*.json` | Lecture récursive + RPC (optionnel) | Fichiers locaux seulement |
| **fireworks** | `~/.config/agent-usage/fireworks.json` + Billing API | Config + HTTP GET | Config locale seulement |

**Normalisation Snapshot v1** :
```lua
{
  version = 1,
  timestamp = 1692000000000,
  agent = "opencode",
  plan = "Free",
  quota = { used = 15000, limit = 50000, reset_ms = 1692086400000, period = "day" },
  balance = { credits = 10.50, currency = "USD", estimated = false },
  speaking = false,
  tokens_today = 45000,
  tokens_by_model = { ["gpt-4o"] = 30000, ["gpt-4o-mini"] = 15000 },
  tokens_by_type = { input = 20000, output = 15000, cache = 10000 },
  limits = { { name="session", used=100, limit=200, reset_ms=..., percent=50 } }
}
```

### 2.3 Widget Barre (`bar_widget.luau`) — Vue Compacte

**Responsabilités** :
- `watch("agent_usage", render)` — réaction immédiate
- Rendu impératif : `barWidget.setGlyph()` + `barWidget.setText()`
- Mapping agent → glyph configurable : opencode=code, claude=bot, codex=terminal, fireworks=flame
- Speaking pulse : animation CSS via `setTimeout` toggle glyph
- Interactions : `onClick` (toggle panel), `onRightClick` (force refresh)
- Tooltip enrichi : quota détaillé, balance, speaking, prochain reset
- Visibilité conditionnelle : `hide_when_idle` setting

**Mapping État → Affichage** :
| État | Glyph (défaut) | Texte | Couleur |
|------|----------------|-------|---------|
| speaking | `pulse` (animé) | `Agent ████ 75%` | Bleu pulse |
| idle | glyph agent | `Agent 45%` | Vert |
| quota_exceeded | `alert` | `Agent LIMIT` | Rouge |
| error | `x-circle` | `Agent ERR` | Rouge |
| disabled | `eye-off` | `Agent OFF` | Gris |

### 2.4 Panel (`panel.luau`) — Vue Détaillée Déclarative

**Responsabilités** :
- `panel.render(ui_tree)` — UI déclarative complète avec accordéons
- Sections : Hero, Limites, Balance, Tokens/Jour, Tokens/Modèle, Sync Status
- `watch("agent_usage", refresh)`, `watch("agent_usage_sync", refresh_sync)`
- Actions utilisateur → IPC vers service → mise à jour état → re-render auto

**Structure UI Tree** :
```lua
panel.render({
  type = "scroll",
  children = {
    -- Hero
    { type = "box", orientation = "horizontal", children = {
      { type = "badge", text = agent:upper(), color = agent_color },
      { type = "text", text = plan, weight = "bold", grow = true },
      { type = "badge", text = auth_status, color = auth_color },
      { type = "button", text = "Refresh", on_click = "ipc:refresh" },
      { type = "button", text = sync_mode=="On" and "Disable Sync" or "Enable Sync",
        on_click = "ipc:toggle_sync" },
    }},

    -- Limites
    { type = "accordion", title = "Limites", default_open = true, children = {
      { type = "list", items = limits, render_item = function(l) return {
        type = "box", children = {
          { type = "text", text = l.name, grow = true },
          { type = "progress", value = l.percent, max = 100 },
          { type = "text", text = string.format("%d/%d (%d%%)", l.used, l.limit, l.percent) },
          { type = "text", text = "Reset: " .. format_time(l.reset_ms) },
        }
      } end },
    }},

    -- Balance (Fireworks)
    { type = "accordion", title = "Balance", default_open = has_balance, children = {
      { type = "gauge", value = balance_ratio, color = "green" },
      { type = "text", text = string.format("$%.2f / $%.2f", spent, funded) },
    }},

    -- Tokens/Jour (7 jours)
    { type = "accordion", title = "Tokens / Jour (7j)", default_open = true, children = {
      { type = "graph", data = tokens_7d, height = 120 },
    }},

    -- Tokens/Modèle
    { type = "accordion", title = "Tokens / Modèle", default_open = true, children = {
      { type = "list", items = tokens_by_model, render_item = function(m) return {
        type = "box", children = {
          { type = "text", text = m.model, grow = true },
          { type = "progress", value = m.percent, max = 100 },
          { type = "text", text = m.tokens },
        }
      } end },
    }},

    -- Sync Status
    { type = "accordion", title = "Sync Multi-Machine", default_open = false, children = {
      { type = "text", text = sync_status },
      { type = "button", text = "Force Sync", on_click = "ipc:force_sync" },
    }},
  }
})
```

### 2.5 Shortcut Control Center (`shortcut.luau`) — Accès Rapide

**Responsabilités** :
- `shortcut.setActive(speaking)` — état visuel (pulse si speaking)
- `onClick()` → IPC toggle panel
- `watch("agent_usage", update)` — sync avec service
- Badge agent actif + speaking pulse

### 2.6 Sync Multi-Machine (Optionnel)

**Architecture** :
```
┌─────────────┐     File Watch          ┌──────────────────┐
│  Machine A  │ ──────────────────────► │  sync_dir/       │
│  (service)  │   writes snapshot.json  │  hostnameA.json  │
└─────────────┘                         └────────┬─────────┘
                                                 │
                    ┌────────────────────────────┘
                    ▼
┌─────────────┐     File Watch          ┌──────────────────┐
│  Machine B  │ ◄────────────────────── │  sync_dir/       │
│  (service)  │   reads all *.json      │  hostnameA.json  │
└─────────────┘                         │  hostnameB.json  │
                                        └──────────────────┘
```

**Fusion** :
- Jours actifs = union par date (pas somme)
- Quotas = max par période (pas somme)
- Rate limits = jamais mergés (par compte)
- Tokens = somme par jour/modèle

### 2.6.2 Sync Read & Merge Implementation (Nouveau)

**Service Functions** :
- `read_sync_snapshots()` : liste `sync_dir`, lit tous `*.json`, parse, valide structure
- `merge_sync_snapshots(snapshots[])` : fusionne selon règles ci-dessus
- `publish_sync_status(merged_sync)` : publie vers `noctalia.state.set("agent_usage_sync", ...)`

**Merge Logic Détail** :
```lua
-- Pour chaque agent dans chaque snapshot device:
-- 1. tokens_daily: union par date (garde max tokens si date existe déjà)
-- 2. tokens_by_model: somme des tokens par modèle
-- 3. tokens_by_type: somme input/output/cache
-- 4. quota/limits: max par période (pas somme - rate limits per account)
-- 5. balance: garde le plus haut funded amount (ne pas merger comptes différents)
-- 5. speaking: true si n'importe quel device speaking

-- devices[]: liste {id, last_seen, primary_agent} pour UI panel
-- last_sync: max timestamp parmi tous devices
```

**Panel Sync UI** (`render_sync()`) :
- Status badge (Activé/Désactivé)
- Sync directory path
- Last sync timestamp (format relatif)
- Device count + liste devices (id, primary_agent, last_seen)
- Buttons: "Forcer Sync" (ipc:force_sync), "Activer/Désactiver" (ipc:toggle_sync)

## 3. Flux de Données

### 3.1 Poll → État Partagé → UI

```
┌─────────┐    runAsync(collectors)    ┌─────────┐    merge/normalize    ┌──────────────┐
│ Service │ ────────────────────────► │ Callback │ ──────────────────► │ state.set()  │
└─────────┘                           └─────────┘                       └──────┬───────┘
                                                                            │
                    ┌────────────────────────────────────────────────────────┘
                    ▼
            ┌───────────────┐     watch(callback)      ┌────────────┐
            │ noctalia.state │ ──────────────────────► │  Widget    │
            │  (shared mem)  │                         │  (render)  │
            └───────────────┘                         └────────────┘
                    │
                    ▼
            ┌───────────────┐                         ┌────────────┐
            │  Panel        │ ◄──── watch ────────── │  Shortcut  │
            │  (render)     │                         │  (active)  │
            └───────────────┘                         └────────────┘
```

### 3.2 Action Utilisateur → Service → État → UI

```
User Click (widget/panel/shortcut)
        │
        ▼
noctalia.runAsync({ "noctalia", "msg", "plugin", ... }, cb)
        │
        ▼
Service onIpc("refresh") → force_collect() → state.set("agent_usage", new)
        │
        ▼
watchers notifiés → widget.render() / panel.refresh() / shortcut.setActive(true)
```

## 4. Gestion d'Erreurs & Robustesse

### 4.1 Stratégie Collectors

```
load_collectors():
  for agent in config.enabled_agents:
    try:
      collector = require("collectors." .. agent)
      if collector.validate_config(config[agent]):
        state.collectors[agent] = collector
        log("Loaded collector: " .. agent)
      else:
        log_warn("Collector config invalid: " .. agent)
    catch err:
      log_warn("Failed to load collector " .. agent .. ": " .. err)
```

### 4.2 Retry & Backoff (API OAuth)

```lua
local MAX_RETRIES = 3
local BASE_DELAY_MS = 1000

function api_call_with_retry(attempt)
  runAsync(cmd, function(result)
    if result.exitCode == 0 then
      consecutive_failures = 0
      parse_and_publish(result.stdout)
    else
      consecutive_failures = consecutive_failures + 1
      if consecutive_failures <= MAX_RETRIES then
        local delay = BASE_DELAY_MS * (2 ^ (consecutive_failures - 1))
        log(string.format("API failed (%d/%d), retry in %dms", consecutive_failures, MAX_RETRIES, delay))
        setTimeout(delay, function() api_call_with_retry(consecutive_failures) end)
      else
        log_error("Max retries reached, using cached data")
        publish_cached_state()
      end
    end
  end)
end
```

### 4.3 Degraded Mode

| Collector Status | Comportement |
|------------------|--------------|
| Fichier absent | Collector disabled, log info |
| Fichier présent mais JSON invalide | Log warn, utiliser cache |
| API OAuth fail | Backoff exponentiel, fallback cache |
| API rate limited | Attendre reset, puis retry |
| Tous collectors disabled | Widget affiche "No agents", service idle |

### 4.4 Timeouts & Guards

| Opération | Timeout | Garde-fou |
|-----------|---------|-----------|
| `runAsync` collector | 5s | `runAsync` kill auto |
| Poll interval | Config (défaut 300s) | `setUpdateInterval` min 60s |
| IPC action | 5s | Callback avec timeout |
| Panel render | < 16ms | UI tree simple |
| Speaking pulse | 500ms toggle | Auto-stop si speaking=false |

## 5. Persistance (`pluginDataDir`)

**Fichiers** :
- `state_cache.json` — dernier snapshot, timestamp, préférences UI
- `sync_cache.json` — cache snapshots multi-machine

**Structure state_cache.json** :
```json
{
  "last_snapshot": { ... },
  "last_poll_ts": 1234567890,
  "panel_geometry": { "width": 480, "height": 520 },
  "user_prefs": { "last_selected_agent": "opencode" }
}
```

**Chargement** : Au `init()` service → `readFile` → `state.set` immédiat → widget affiche cache < 100ms avant poll frais.

**Sauvegarde** : Debounced (500ms) sur changement état significatif + à `shutdown()`.

## 6. Configuration (Settings)

### 6.1 Plugin-Level (partagés toutes entrées)

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `refresh_interval_sec` | int | 300 | Intervalle poll (60-3600) |
| `enabled_agents` | string[] | ["opencode","claude","codex","fireworks"] | Agents activés |
| `sync_mode` | enum | "Off" | "Off" / "On" |
| `sync_dir` | path | "" | Dossier sync (Syncthing/Dropbox) |
| `sync_device_id` | string | hostname | Nom device stable |
| `show_speaking_indicator` | bool | true | Pulse animation |

### 6.2 Widget-Level (par instance)

| Clé | Type | Défaut | Description |
|-----|------|--------|-------------|
| `glyph_opencode` | glyph | "code" | Glyph opencode |
| `glyph_claude` | glyph | "bot" | Glyph claude |
| `glyph_codex` | glyph | "terminal" | Glyph codex |
| `glyph_fireworks` | glyph | "flame" | Glyph fireworks |
| `hide_when_idle` | bool | false | Masquer si aucun agent actif |

## 7. IPC Contract (Plugin ↔ Noctalia Shell)

### 7.1 Service Commands (cibles : `all`)

| Commande | Payload | Description |
|----------|---------|-------------|
| `refresh` | `{}` | Force collect immédiat |
| `toggle_sync` | `{}` | Toggle sync_mode On/Off |
| `force_sync` | `{}` | Écriture immédiate snapshot dans sync_dir |

### 7.2 Panel Actions (via `panel.onAction`)

Même contrat, préfixé `ipc:` dans `on_click`.

## 8. Sécurité & Sandbox

- **Pas de credentials** : Plugin ne touche jamais tokens/API keys
- **IPC only** : Communication via Noctalia, pas de socket réseau
- **runAsync argv array** : Pas de shell injection
- **Paths validation** : Collectors lisent seulement paths configurés (sous `$HOME`)
- **Read-only config** : Plugin lit settings, ne les écrit pas (Noctalia gère)
- **Respect offline_mode** : Plugin passif si `shell.offline_mode=true`

## 9. Tests & Validation

### 9.1 Scénarios Critiques

| Scénario | Test | Critère Pass |
|----------|------|--------------|
| opencode installé, usage.json présent | Activer plugin → widget montre "opencode 45%" | Glyph + quota correct |
| Claude OAuth configuré | Widget affiche quota Claude + balance | Données API + cache |
| opencode absent | Collector disabled gracieusement | Widget n'affiche pas opencode |
| API rate limited | Backoff → cache → retry | Pas de crash, cache utilisé |
| Sync activé + Syncthing | Snapshot écrit/lu dans sync_dir | Panel montre multi-machine |
| Speaking pulse | `speaking=true` → pulse animation | Glyph pulse visible |

### 9.2 Commandes Test Rapide

```bash
# Activer plugin local
noctalia msg plugins enable roddygithub/agent-usage

# Voir logs service
journalctl --user -f -u noctalia | grep -E "\[agent-usage\]"

# Test IPC refresh
noctalia msg plugin roddygithub/agent-usage:service all refresh

# Test panel
noctalia msg panel-toggle roddygithub/agent-usage:detail

# Recharger plugin après modif code
noctalia msg plugins disable roddygithub/agent-usage && \
noctalia msg plugins enable roddygithub/agent-usage
```

## 10. Évolutions Futures (Post-v1)

| Feature | Complexité | Dépendances |
|---------|------------|-------------|
| Launcher provider `/agent` search | Moyenne | API search agents |
| Notifications push quota critique | Faible | `noctalia.notify` + setting |
| Export CSV/JSON historique | Faible | `pluginDataDir()` + JSON encode |
| Dashboard web local (HTTP) | Moyenne | `noctalia.runAsync` HTTP server |
| Intégration Noctalia panel natif | Faible | `noctalia.getSetting` |

---

*Architecture validée pour Noctalia v5 Beta (plugin_api 27). Protocole v1 figé dans `specs/protocol-v1.openspec.yaml`.*