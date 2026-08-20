---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# settings/settings.py

## Rattachements

**Composant parent** : [[20-Composants/settings]]

**Lancé par** :
- [[20-Composants/settings/settings-sh]] — démarre le serveur (nohup, pidfile)

**Consommé par** :
- [[20-Composants/settings/main-qml]] — XHR vers http://127.0.0.1:8770/api/*

**Fichiers lus/écrits** :
- [[20-Composants/settings/settings-json]] — état du panneau
- [[20-Composants/hypr/hypridle-conf]] — régénéré (template timeouts, restart hypridle)
- [[20-Composants/hypr/keybinds-user-conf]] — overrides écrits (POST /api/keybinds)
- [[20-Composants/hypr/keybinds-conf]] — binds parsés (GET /api/keybinds)
- [[20-Composants/waybar/config]] — format d'horloge patché (POST /api/clock)
- [[20-Composants/hypr/conf.d/general-conf]], [[20-Composants/hypr/conf.d/decoration-conf]], [[20-Composants/hypr/conf.d/animations-conf]] — section SYSTÈME
- [[20-Composants/scripts/theme-apply-sh]] — exécuté après palette/horloge (recharge waybar/hyprlock)
- [[20-Composants/scripts/theme-apply-py]] — génère `cc/qml/Palette.qml` (lu pour /api/palette)

**Routes API (127.0.0.1:8770)** : `/api/health`, `/api/state`, `/api/palette`, `/api/system`, `/api/keybinds`, `/api/veille`, `/api/clock`, `/api/cc`, `/api/keybinds/reset`, `/api/wallpaper`, `/api/close`
