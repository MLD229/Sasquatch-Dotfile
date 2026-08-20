---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/player.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/mpd-py]] (status/toggle), [[20-Composants/cc/web_bridge-py]] (web_status, push_command), [[20-Composants/cc/config-py]] (RUNTIME_DIR)

**Importé par** : [[20-Composants/cc/server-py]] — /api/music/status, /api/music/toggle|next|prev|stop|seek, /albumart

**Sources unifiées** : playerctl (MPRIS : navigateurs/Spotify…), MPD, pactl (fallback pulse), web ([[20-Composants/cc/browser-bridge/background-js]])

**Lance** : mpv (playlist audio locale, `start_new_session`)
