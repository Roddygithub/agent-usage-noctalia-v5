# Progress Tracking — Agent Usage Monitor for Noctalia V5

## Statut Global

| Phase | Statut | Progression | Début | Fin Estimée | Notes |
|-------|--------|-------------|-------|-------------|-------|
| **P0 - Fondations, Spec, Collectors Core** | 🔴 Non commencé | 0% | J+0 | J+4 | Spec v1, collectors opencode/claude, service skeleton |
| **P1 - Widget Barre + Settings + Shortcut** | 🔴 Non commencé | 0% | J+4 | J+7 | Widget, keybinds, shortcut, settings |
| **P2 - Panel Détaillé** | 🔴 Non commencé | 0% | J+7 | J+11 | UI déclarative, accordéons, graphiques |
| **P3 - Collectors Restants + Sync** | 🔴 Non commencé | 0% | J+11 | J+14 | Codex, Fireworks, sync multi-machine |
| **P4 - Polish, Tests, Release** | 🔴 Non commencé | 0% | J+14 | J+17 | CI/CD, docs, release v1.0.0 |

**Progression Globale** : 5% (Architecture + Spec + Planning complets)

---

## Journal de Bord

### 2026-08-15 — Initialisation & Architecture Complète
- ✅ Repository structure créée
- ✅ README.md avec architecture, installation, usage, distribution
- ✅ AGENTS.md : contraintes engineering, security, quality, tooling
- ✅ Memory bank initialisée :
  - `prd.md` : 15 user stories (P0-P2), 8 critères done, 5 risques
  - `specs/protocol-v1.openspec.yaml` : Spec OpenAPI 3.0.3 complète (header, JSON Lines, schemas Snapshot/CollectorConfig/PluginSettings, paths, x-protocol, x-collector-contract, x-testing)
  - `tech-stack.md` : Luau/Noctalia API 27, collectors Lua, Luau-lsp, BMAD/Superpowers/Vibe Coding
  - `architecture.md` : 5 composants détaillés, flux données, error handling, persistance, IPC, security, tests
  - `implementation-plan.md` : 4 phases, 40+ tâches, 14.5 jours, 6 jalons, risques
- ✅ Git init + structure dossiers (`scripts/`, `memory-bank/`, `collectors/`, `specs/`, `translations/`, `.opencode/skills/`, `.github/workflows/`)

---

## Prochaines Actions Immédiates

### Phase 0 — Fondations (Cette session)

1. **Créer `plugin.toml` manifest complet** avec :
   - Manifest metadata (id, name, version, plugin_api=27, author)
   - `[[service]] id="collector" entry="service.luau"`
   - `[[widget]] id="status" entry="bar_widget.luau"` + settings widget
   - `[[panel]] id="detail" entry="panel.luau"` + config
   - `[[shortcut]] id="toggle" entry="shortcut.luau"`
   - Settings plugin-level (refresh_interval_sec, enabled_agents, sync_mode, sync_dir, sync_device_id, show_speaking_indicator)
   - Keybinds : `Ctrl+Alt+A` (toggle panel), `Ctrl+Alt+R` (refresh)

2. **Créer `service.luau` v0.1** :
   - `load_collectors()` : require `collectors/<agent>.lua` pour agents activés
   - `validate_collectors()` : appelle `validate_config()`
   - `poll_loop()` : `setUpdateInterval` + `runAsync` par collector → merge → `state.set("agent_usage")`
   - `onIpc(payload)` : `refresh` → force_collect(), `toggle_sync` → toggle sync_mode
   - `init()` / `shutdown()` / `update()`

3. **Créer collectors de base** :
   - `collectors/opencode.lua` : lit `~/.config/opencode/usage.json`
   - `collectors/claude.lua` : lit `~/.claude/stats-cache.json` + `history.jsonl`

4. **Test local P0** :
   ```bash
   ./scripts/bootstrap-bmad.sh
   ./scripts/bootstrap-superpowers.sh
   ./scripts/bootstrap-vibe-coding.sh
   ln -s ~/Projets/agent-usage-noctalia-v5 ~/.local/share/noctalia/plugins/agent-usage
   noctalia msg plugins enable roddygithub/agent-usage
   journalctl --user -f -u noctalia | grep "\[agent-usage\]"
   ```

---

## Dépendances Externes à Valider

| Dépendance | Statut | Action Requise |
|------------|--------|----------------|
| `luau-lsp` installé | ❓ Inconnu | `luau-lsp --version` |
| `stylua` installé | ❓ Inconnu | `stylua --version` |
| Noctalia v5 installé | ❓ Inconnu | `noctalia --version` |
| `opencode` installé | ❓ Inconnu | `opencode --version` + `~/.config/opencode/usage.json` |
| `claude` CLI installé | ❓ Inconnu | `claude --version` + `~/.claude/stats-cache.json` |
| `codex` CLI installé | ❓ Inconnu | `codex --version` + `~/.codex/sessions/` |
| `fireworks` API key | ❓ Inconnu | `FIREWORKS_API_KEY` env var |

---

## Décisions Techniques Enregistrées

| Date | Décision | Raison | Alternative Rejetée |
|------|----------|--------|---------------------|
| 2026-08-15 | Plugin API 27 (current) | Accès complet features (panel, runAsync argv, desktop_widget) | API 9 (stable mais limité) |
| 2026-08-15 | Protocol v1 figé OpenSpec | Single source of truth, round-trip testable, versioning clair | Ad-hoc JSON, pas de versioning |
| 2026-08-15 | Collectors comme modules Lua purs | Testables, isolés, single responsibility, TDD friendly | Functions inline dans service (pas testable) |
| 2026-08-15 | BMAD + Superpowers + Vibe Coding | Memory bank durable, TDD enforced, subagent-driven-dev | Une seule méthodologie (moins robuste) |
| 2026-08-15 | Protocol header `AGENT_USAGE/1.0` | Versioning clair, forward compatibility | Pas de header (pas de versioning) |
| 2026-08-15 | Sync via fichiers JSON dans sync_dir | Simple, pas de DB, compatible Syncthing/Dropbox/rsync | SQLite/Redis (overkill) |

---

## Prochaine Session - Checklist

- [ ] Créer `plugin.toml` manifest complet
- [ ] Créer `service.luau` v0.1 (load collectors, poll, IPC)
- [ ] Créer `collectors/opencode.lua` + `collectors/claude.lua`
- [ ] Créer `scripts/bootstrap-bmad.sh`, `bootstrap-superpowers.sh`, `bootstrap-vibe-coding.sh`
- [ ] Test activation plugin local
- [ ] Valider détection collectors + poll réussi
- [ ] Mettre à jour `progress.md` avec résultats réels

---

## Tâches Détaillées Prochaines (P0 → P1)

### P0 - Fondations (À faire maintenant)
- [ ] P0.1 ✅ Repo structure + BMAD bootstrap (scripts créés)
- [ ] P0.2 ✅ Protocol Spec v1 (specs/protocol-v1.openspec.yaml)
- [ ] P0.3 ✅ Protocol Round-trip Test (specs/test_protocol_roundtrip.lua - à créer)
- [ ] P0.4 ✅ Collector opencode (collectors/opencode.lua - à créer)
- [ ] P0.5 ✅ Collector claude (collectors/claude.lua - à créer)
- [ ] P0.6 ✅ Service Skeleton (service.luau - à créer)
- [ ] P0.7 ✅ Plugin.toml Manifest (plugin.toml - à créer)
- [ ] P0.8 ✅ Settings Plugin-level (dans plugin.toml)
- [ ] P0.9 ✅ CI Base (`.github/workflows/ci.yml` - à créer)
- [ ] **TEST P0** : Activer plugin, vérifier logs, IPC, state publishing

### P1 - Widget Barre (Après P0 validé)
- [ ] P1.1 ✅ Widget entry + manifest (plugin.toml)
- [ ] P1.2 ✅ Rendu impératif (bar_widget.luau - à créer)
- [ ] P1.3 ✅ Mapping glyphes configurables (bar_widget.luau + plugin.toml)
- [ ] P1.4 ✅ Speaking Pulse (bar_widget.luau)
- [ ] P1.5 ✅ Tooltip enrichi (bar_widget.luau)
- [ ] P1.6 ✅ Clic gauche toggle panel (bar_widget.luau)
- [ ] P1.7 ✅ Clic droit refresh (bar_widget.luau)
- [ ] P1.8 ✅ Setting hide_when_idle (bar_widget.luau + plugin.toml)
- [ ] P1.9 ✅ Watch state réactif (bar_widget.luau)
- [ ] P1.10 ✅ Keybinds globaux (plugin.toml keybinds)
- [ ] P1.11 ✅ Shortcut Control Center (shortcut.luau - à créer)
- [ ] **TEST P1** : Widget dans barre, keybinds, settings gear, shortcut

---

*Dernière MAJ : 2026-08-15 — Architecture + Spec + Planning complets, prêt pour implémentation P0*