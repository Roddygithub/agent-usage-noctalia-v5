# PRD — Agent Usage Monitor for Noctalia V5

## 1. Contexte & Objectif

**Produit** : Plugin Noctalia V5 natif (Luau) surveillant l'usage des agents de code IA (opencode, Claude, Codex, Fireworks) et affichant quotas, balance, tokens en temps réel.

**Cible** : Développeurs Arch/Hyprland/Noctalia utilisant des agents IA pour coder.

**Problème** : Pas de visibilité native sur l'usage des agents (quotas, crédits, tokens/jour). Il faut ouvrir terminaux, dashboards web, ou lancer commandes CLI.

**Solution** : Plugin Noctalia exposant :
- Widget barre : quota % + indicateur speaking + glyph agent
- Panel détaillé : limites, balance, tokens/jour, tokens/modèle, historique
- Shortcut Control Center : toggle rapide
- Service collecteur : lit fichiers locaux + APIs OAuth, publie état partagé

## 2. Utilisateurs & Personas

| Persona | Besoins |
|---------|---------|
| **Dev Arch/Hyprland** | Vue d'état instantanée, pas de terminal, raccourcis clavier |
| **Utilisateur multi-agents** | Vue unifiée opencode + Claude + Codex + Fireworks |
| **Dev multi-machines** | Sync usage via Syncthing/Dropbox, agrégation multi-devices |

## 3. Fonctionnalités (User Stories)

### 3.1 Widget Barre (Core - P0)
- **US-01** : Afficher glyph agent + quota % + indicateur speaking pulse
- **US-02** : Clic gauche → toggle panel détaillé
- **US-03** : Clic droit → force refresh collectors
- **US-04** : Tooltip : quota détaillé, balance, speaking status, prochain reset
- **US-05** : Setting `hide_when_idle` : masquer si aucun agent actif

### 3.2 Service Collecteur (Core - P0)
- **US-10** : Démarrage auto, singleton par session Noctalia
- **US-11** : Poll collectors toutes les 300s (configurable)
- **US-12** : Collecteurs par agent :
  - **opencode** : `~/.config/opencode/usage.json` (tokens, plan, reset)
  - **claude** : `~/.claude/stats-cache.json` + `history.jsonl` + OAuth API
  - **codex** : `~/.codex/sessions/` + app-server RPC
  - **fireworks** : Billing API + `~/.config/agent-usage/fireworks.json`
- **US-13** : Normalisation → snapshot v1 partagé via `noctalia.state.set("agent_usage", table)`
- **US-14** : Gestion erreurs : collector manquant → disabled ; API failure → cache + warning
- **US-15** : IPC `refresh` → force collect immédiat

### 3.3 Panel Détaillé (P1)
- **US-20** : Ouverture via `noctalia msg panel-toggle` ou clic widget
- **US-21** : Sections : Hero (agent+plan+auth), Limites (% + meter + reset), Balance (fuel gauge), Tokens/Jour (7 jours), Tokens/Modèle (breakdown), Sync Status
- **US-22** : UI déclarative `panel.render(ui_tree)` avec accordéons, graphiques, meters
- **US-23** : Actions : refresh, toggle sync, switch agent

### 3.4 Shortcut Control Center (P1)
- **US-30** : Tuile "Agent Usage" avec glyph agent actif
- **US-31** : Clic → toggle panel
- **US-32** : Badge speaking pulse si agent en cours d'utilisation

### 3.5 Sync Multi-Machine (P2)
- **US-40** : `sync_mode: "On"` → écrit snapshot dans `sync_dir` (Syncthing/Dropbox/rsync)
- **US-41** : Fusionne tous `*.json` dans `sync_dir` → union jours actifs, max quotas
- **US-42** : Rate limits jamais mergés (par compte)

### 3.6 Settings Plugin (P0)
- **US-50** : `refresh_interval_sec` (int, 60-3600, default=300)
- **US-51** : `enabled_agents` (list, default=["opencode","claude","codex","fireworks"])
- **US-52** : `sync_mode` (enum: Off/On)
- **US-53** : `sync_dir` (path)
- **US-54** : `sync_device_id` (string, default=hostname)
- **US-55** : `show_speaking_indicator` (bool, default=true)

## 4. Contraintes Techniques

| Contrainte | Détail |
|------------|--------|
| **Plugin API** | `plugin_api = 27` (Noctalia v5 beta current) |
| **Langage** | Luau (`--!nonstrict`), VM isolée par entrée |
| **Runtime** | Off UI thread, budget ~2ms/appel |
| **Protocol** | `AGENT_USAGE/1.0` + JSON Lines (specs/protocol-v1.openspec.yaml) |
| **Collectors** | Modules Lua purs, testables, isolés |
| **Dépendances** | `seafile-client` non requis ; APIs OAuth optionnelles |
| **Noctalia V5** | Beta — APIs peuvent changer, viser compat 3-27 |

## 5. Definition of Done

- [ ] Plugin s'installe via `noctalia msg plugins source add local path ...` + enable
- [ ] Widget apparaît dans "Add widget picker", configurable (gear)
- [ ] Service démarre, collectors tournent, publient état sans erreur
- [ ] Widget affiche quota % + speaking pulse en temps réel
- [ ] Clic gauche → panel s'ouvre ; clic droit → refresh
- [ ] Panel affiche limites, balance, tokens/jour, tokens/modèle
- [ ] Shortcut Control Center visible et fonctionnel
- [ ] Settings persistés via `pluginDataDir()` survivent restart
- [ ] Pas de crash Luau (try/catch sur tous collectors)
- [ ] Logs `noctalia.log()` utiles (préfixe `[agent-usage]`)
- [ ] Protocol round-trip test passe (TS → Rust → Lua)

## 6. Hors Scope (v1)

- Dashboard web / API REST
- Alertes push (notifications système) — faire simple d'abord
- Gestion teams/organisations (quotas partagés)
- Export CSV/JSON historique complet
- Launcher provider `/agent` search

## 7. Risques & Mitigations

| Risque | Probabilité | Impact | Mitigation |
|--------|-------------|--------|------------|
| Fichiers usage opencode/Claude changent format | Moyenne | Élevé | Versioning collector, fallback gracieux, tests |
| API OAuth Claude/Codex rate limited | Faible | Moyen | Cache local, backoff exponentiel, fallback cache |
| Noctalia plugin API breaking change | Élevée | Élevé | Cibler API 27, surveiller changelog, tests CI |
| Fichiers locaux absents (agent pas installé) | Élevée | Faible | Collector disabled gracieusement, pas d'erreur |
| Sync multi-machine conflits | Faible | Moyen | Union par date, pas somme ; rate limits non mergés |

## 8. Métriques de Succès

- Temps démarrage service < 200ms
- Poll 300s → CPU plugin < 0.5%
- Zéro crash Luau en 1 semaine usage continu
- Widget met à jour quota < 1s après refresh
- Protocol round-trip 100% compatible (specs test)