# Implementation Plan — Agent Usage Monitor for Noctalia V5

## Vue d'Ensemble Phases

| Phase | Focus | Durée Est. | Livrable |
|-------|-------|------------|----------|
| **P0** | Fondations, Protocol Spec, Collectors Core | 3-4 jours | Spec v1 figée, collectors opencode/claude, service skeleton |
| **P1** | Widget Barre + Settings + Shortcut | 2-3 jours | Widget fonctionnel, keybinds, settings gear |
| **P2** | Panel Détaillé (UI déclarative) | 3-4 jours | Panel complet avec accordéons, graphiques, sync |
| **P3** | Collectors Restants (Codex, Fireworks) + Sync | 2-3 jours | Tous collectors, multi-machine sync |
| **P4** | Polish, Tests, Distribution Pipeline | 2-3 jours | CI/CD, AUR-ready, docs, release v1.0.0 |

**Total : ~12-17 jours** (étalable sur 4-5 semaines temps partiel)

---

## Phase 0 — Fondations, Protocol Spec, Collectors Core (P0)

### Objectif
Spec protocol v1 figée (OpenSpec), collectors opencode/claude fonctionnels, service skeleton avec poll + state publishing.

### Tâches

| ID | Tâche | Description | Critères Acceptation |
|----|-------|-------------|----------------------|
| P0.1 | **Repo structure + BMAD bootstrap** | Créer dossiers, `scripts/bootstrap-*.sh`, `memory-bank/` | `./scripts/bootstrap-bmad.sh` passe |
| P0.2 | **Protocol Spec v1 (OpenSpec)** | `specs/protocol-v1.openspec.yaml` : header, JSON Lines, schemas Snapshot, CollectorConfig, PluginSettings | Spec valide OpenAPI 3.0.3, round-trip testable |
| P0.3 | **Protocol Round-trip Test** | `specs/test_protocol_roundtrip.lua` : serialize TS → deserialize Lua → compare | Test passe, schema validation |
| P0.3 | **Collector opencode** | `collectors/opencode.lua` : lit `~/.config/opencode/usage.json`, retourne snapshot v1 | Parse JSON, gère absent/invalide, retourne snapshot valide |
| P0.4 | **Collector claude** | `collectors/claude.lua` : `stats-cache.json` + `history.jsonl` + OAuth optionnel | Parse cache local, OAuth optionnel avec backoff |
| P0.5 | **Service Skeleton** | `service.luau` : load collectors, poll loop, `state.set("agent_usage")`, IPC refresh | `noctalia msg plugins enable` → service démarre, poll toutes les 300s |
| P0.6 | **Plugin.toml Manifest** | Manifest complet : id, name, version, plugin_api=27, entries (service, widget, panel, shortcut), settings | `noctalia msg plugins enable` → plugin visible dans Settings |
| P0.7 | **Settings Plugin-level** | Déclarer dans plugin.toml : refresh_interval_sec, enabled_agents, sync_mode, sync_dir, sync_device_id, show_speaking_indicator | Gear visible dans Settings, valeurs par défaut fonctionnelles |
| P0.8 | **CI Base** | `.github/workflows/ci.yml` : luau-lsp check, protocol round-trip, collector unit tests | PR → CI verte |

### Définition de Done P0
- [ ] Spec v1 figée dans `specs/protocol-v1.openspec.yaml`
- [ ] Collectors opencode + claude passent unit tests
- [ ] `noctalia msg plugins enable roddygithub/agent-usage` → service démarre
- [ ] `journalctl -f` montre `[agent-usage] poll ok` toutes les 300s
- [ ] `noctalia msg plugin ...:service all refresh` → force collect immédiat
- [ ] Settings gear visible dans Settings → Plugins
- [ ] CI verte sur main

---

## Phase 1 — Widget Barre + Settings + Shortcut (P1)

### Objectif
Widget barre fonctionnel, configurable, keybinds globaux, shortcut Control Center.

### Tâches

| ID | Tâche | Description | Critères Acceptation |
|----|-------|-------------|----------------------|
| P1.1 | **Widget entry + manifest** | `[[widget]] id="status" entry="bar_widget.luau"` + settings widget-level | Widget apparaît dans "Add widget picker" |
| P1.2 | **Rendu impératif** | `update()` → `state.get("agent_usage")` → `barWidget.setGlyph()` + `setText()` | Glyph/text changent en temps réel |
| P1.3 | **Mapping glyphes configurables** | Settings : `glyph_opencode`, `glyph_claude`, `glyph_codex`, `glyph_fireworks` | User peut changer glyphes via settings widget |
| P1.4 | **Speaking Pulse** | `speaking=true` → animation pulse (setTimeout toggle glyph) | Pulse visible quand `speaking=true` |
| P1.5 | **Tooltip enrichi** | Quota détaillé, balance, speaking, prochain reset, agent actif | Info riche au survol |
| P1.6 | **Clic gauche → toggle panel** | `onClick()` → `noctalia.togglePanel("roddygithub/agent-usage:detail")` | Panel s'ouvre au clic gauche |
| P1.7 | **Clic droit → force refresh** | `onRightClick()` → IPC `refresh` | Collect immédiat déclenché |
| P1.8 | **Setting hide_when_idle** | Si `true` et aucun agent actif → `setVisible(false)` | Widget disparaît quand tout idle |
| P1.9 | **Watch state réactif** | `noctalia.state.watch("agent_usage", render)` | Pas de lag visible |
| P1.10 | **Keybinds globaux** | `Ctrl+Alt+A` (toggle panel), `Ctrl+Alt+R` (force refresh) dans plugin.toml | Keybinds listés dans Settings → Keybinds, fonctionnels |
| P1.11 | **Shortcut Control Center** | `[[shortcut]] id="toggle" entry="shortcut.luau"` + `shortcut.setActive(speaking)` | Tuile visible, clic → toggle panel |

### Définition de Done P1
- [ ] Widget ajouté à une barre → affiche quota + glyph agent actif
- [ ] Speaking pulse visible quand agent actif
- [ ] Clic gauche → panel s'ouvre (P2 requis pour panel complet)
- [ ] Clic droit → refresh immédiat
- [ ] Settings widget (gear) → tous réglages fonctionnels + persistés
- [ ] `hide_when_idle=true` → widget masqué si aucun agent actif
- [ ] Keybinds `Ctrl+Alt+A` / `Ctrl+Alt+R` fonctionnels
- [ ] Shortcut Control Center visible et fonctionnel

---

## Phase 2 — Panel Détaillé (P2)

### Objectif
Panel riche (UI déclarative) avec accordéons, graphiques, sync status.

### Tâches

| ID | Tâche | Description | Critères Acceptation |
|----|-------|-------------|----------------------|
| P2.1 | **Panel entry + manifest** | `[[panel]] id="detail" entry="panel.luau" width=520 height=580 placement="floating" position="center"` | `noctalia msg panel-toggle roddygithub/agent-usage:detail` ouvre panel |
| P2.2 | **UI déclarative - Structure** | `panel.render(ui_tree)` avec `ui.scroll` → sections Hero, Limites, Balance, Tokens/Jour, Tokens/Modèle, Sync | Scroll fluide, sections distinctes |
| P2.2 | **Hero Section** | Badge agent + plan + auth status + boutons Refresh / Toggle Sync | Boutons fonctionnels, état visuel cohérent |
| P2.3 | **Section Limites** | `ui.accordion` + `ui.list` + `ui.progress` par limite (session, weekly, etc.) | Progress bars + % + reset timer |
| P2.4 | **Section Balance** | Gauge circulaire (Fireworks) + fuel gauge + funded vs spent | Visible seulement si balance dispo |
| P2.5 | **Tokens/Jour (7j)** | `ui.graph` ou `ui.chart` : barres 7 derniers jours, today bold | Graphique lisible, today highlighted |
| P2.6 | **Tokens/Modèle** | `ui.list` + progress bars par modèle + input/output/cache split | Breakdown complet par modèle |
| P2.7 | **Sync Status** | Multi-machine status + bouton Force Sync + last sync time | Status clair, bouton fonctionnel |
| P2.8 | **Accordéons** | Toutes sections repliables/dépliables, état persisté | UX propre, pas de scroll infini |
| P2.9 | **Watch cohérent** | `state.watch("agent_usage", refresh)`, `state.watch("agent_usage_sync", refresh_sync)` | Panel se met à jour sans lag |
| P2.10 | **Graphiques fallback** | Si `ui.graph` indisponible → ASCII/bar simples | Graceful degradation |

### Définition de Done P2
- [ ] Panel s'ouvre/ferme correctement (Esc, clic extérieur)
- [ ] Toutes sections affichent données réelles temps réel
- [ ] Boutons Refresh / Toggle Sync fonctionnels
- [ ] Graphiques tokens/jour + tokens/modèle visibles
- [ ] Sync status affiché correctement
- [ ] Sections repliables/dépliables
- [ ] Pas de fuite mémoire

---

## Phase 3 — Collectors Restants + Sync (P3)

### Objectif
Collectors Codex + Fireworks complets, sync multi-machine fonctionnelle.

### Tâches

| ID | Tâche | Description | Critères Acceptation |
|----|-------|-------------|----------------------|
| P3.1 | **Collector Codex** | `collectors/codex.lua` : lit `~/.codex/sessions/*.json` + RPC optionnel | Parse sessions, tokens_by_model, tokens_by_type, speaking |
| P3.2 | **Collector Fireworks** | `collectors/fireworks.lua` : Config locale + Billing API (optionnel) | Balance estimée + tokens, config `fundedAmount` |
| P3.3 | **Sync Mode** | `sync_mode: "On"` → écrit snapshot dans `sync_dir/hostname.json` | Fichier écrit à chaque poll, format JSON v1 |
| P3.3 | **Sync Read** | Lit tous `*.json` dans `sync_dir`, fusionne : union jours actifs, max quotas | Panel affiche données agrégées multi-machine |
| P3.4 | **Sync UI** | Panel section Sync : status, devices list, last sync, force sync button | Status clair, bouton force sync fonctionnel |
| P3.5 | **Conflict Resolution** | Rate limits non mergés (par compte), tokens/jour union par date | Fusion correcte, pas de double comptage |
| P3.6 | **Settings Sync** | `sync_mode` (Off/On), `sync_dir`, `sync_device_id`, `sync_file_name` | Gear settings complet |

### Définition de Done P3
- [ ] Collector Codex : tokens_by_model + tokens_by_type + speaking
- [ ] Collector Fireworks : balance estimée + tokens
- [ ] Sync Mode On → écriture `sync_dir/hostname.json` à chaque poll
- [ ] Panel lit tous snapshots dans `sync_dir`, fusion correcte
- [ ] Rate limits non mergés, tokens/jour union par date
- [ ] Force Sync bouton fonctionnel

---

## Phase 4 — Polish, Tests, Distribution (P4)

### Objectif
Robustesse, CI/CD release, docs, publication v1.0.0.

### Tâches

| ID | Tâche | Description | Critères Acceptation |
|----|-------|-------------|----------------------|
| P4.1 | **Persistance pluginDataDir** | `state_cache.json` : dernier snapshot, panel geometry, prefs | Restart Noctalia → widget affiche cache < 100ms |
| P4.2 | **Agent absent handling** | Collector disabled gracieusement si fichiers/API absents | Pas d'erreur, widget n'affiche pas agent |
| P4.3 | **Degraded mode** | API fail → cache + warning, pas de crash | Logs clairs, widget affiche données cachées |
| P4.4 | **Traductions en.json** | Toutes strings UI dans `translations/en.json` | Prêt pour Noctalia Translate |
| P4.4 | **README complet** | Install, config, usage, IPC, troubleshooting, architecture | Doc utilisateur + dev complète |
| P4.5 | **CI/CD Release** | `release.yml` : tag `v*` → build → GitHub Release + assets | `git tag v1.0.0 && git push --tags` → Release |
| P4.5 | **Protocol Round-trip CI** | Test TS serialize → Lua deserialize → compare | CI verte sur protocol |
| P4.6 | **Collector Unit Tests** | `collectors/test_*.lua` pour chaque collector | `lua collectors/test_collectors.lua` passe |
| P4.7 | **Protocol Round-trip CI** | TS serialize → Lua deserialize → compare schema | CI verte |
| P4.8 | **Integration Test Script** | `scripts/test_integration.sh` : Vesktop headless + plugin | Pipeline CI verte (optionnel) |
| P4.9 | **CHANGELOG** | `CHANGELOG.md` depuis v0.1.0 → v1.0.0 | Historique clair |
| P4.10 | **Release v1.0.0** | Tag `v1.0.0` → pipeline complète → artefacts publiés | Release publique |
| P4.11 | **Community PR** | Fork `noctalia-dev/community-plugins`, ajouter plugin, template PR | Plugin dispo dans source `community` |

### Définition de Done P4
- [ ] Restart Noctalia → widget fonctionnel immédiatement (cache)
- [ ] Agent absent → pas d'erreur, disabled gracieusement
- [ ] API fail → cache + warning, pas de crash
- [ ] Traductions complètes
- [ ] Release v1.0.0 taggée, artefacts publiés
- [ ] Plugin dans `noctalia-dev/community-plugins` (PR ouverte)

---

## Dépendances & Ordre

```
P0.1 → P0.2 → P0.3 → P0.4 → P0.5 → P0.6 → P0.7 → P0.8
                                        ↓
P1.1 → P1.2 → P1.3 → P1.4 → P1.5 → P1.6 → P1.7 → P1.8 → P1.9 → P1.10 → P1.11
                                        ↓
P2.1 → P2.2 → P2.3 → P2.4 → P2.5 → P2.6 → P2.7 → P2.8 → P2.9 → P2.10
                                        ↓
P3.1 → P3.2 → P3.3 → P3.4 → P3.5 → P3.6
                                        ↓
P4.1 → P4.2 → P4.3 → P4.4 → P4.5 → P4.6 → P4.7 → P4.8 → P4.9 → P4.10 → P4.11
```

---

## Estimation Effort Total

| Phase | Jours-homme | Notes |
|-------|-------------|-------|
| P0 | 3.5 | Spec + 2 collectors + service skeleton + CI |
| P1 | 2.5 | Widget + keybinds + shortcut + settings |
| P2 | 3.5 | Panel déclaratif complet + graphiques |
| P3 | 2.5 | 2 collectors + sync complet |
| P4 | 2.5 | Polish, tests, CI/CD, release |
| **Total** | **~14.5 jours** | Étalable sur 4-5 semaines temps partiel |

---

## Jalons Clés (Milestones)

| Jalon | Critère | Date Cible |
|-------|---------|------------|
| **M1 - Protocol Ready** | P0 Done : spec v1 figée, collectors opencode/claude, service poll | J+4 |
| **M2 - Widget Visible** | P1 Done : widget barre, keybinds, shortcut, settings | J+7 |
| **M3 - Panel Complet** | P2 Done : panel déclaratif complet, graphiques | J+11 |
| **M4 - Feature Complete** | P3 Done : tous collectors, sync multi-machine | J+14 |
| **M5 - Release Ready** | P4 Done : robuste, testé, documenté, CI/CD | J+17 |
| **M6 - Published** | P4.11 Done : PR community-plugins ouverte | J+18 |

---

## Risques & Plans B

| Risque | Probabilité | Impact | Plan B |
|--------|-------------|--------|--------|
| API OAuth Claude/Codex change | Moyenne | Bloquant | Cache local robuste, fallback gracieux, versionning collector |
| `ui.graph`/`ui.chart` indisponible | Faible | Dégradé P2 | Fallback ASCII/bar simples, documenter limitation |
| `opencode` usage.json format change | Moyenne | Dégradé P0 | Collector versioning, fallback gracieux, test CI |
| Sync multi-machine edge cases | Faible | Mineur | Fusion conservative (union days, max quotas), logs détaillés |
| Noctalia plugin API breaking change | Élevée | Élevé | Cibler API 27, tests sur nightly, versionning plugin_api |

---

## Commandes Validation Rapide (Dev Loop)

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

# Test protocol round-trip
lua specs/test_protocol_roundtrip.lua

# Test collectors
lua collectors/test_collectors.lua
```