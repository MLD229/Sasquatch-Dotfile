---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/playlist.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] (RUNTIME_DIR), [[20-Composants/cc/mpd-py]] (primitives `_mpd_*`)

**Importé par** : [[20-Composants/cc/server-py]] — routes /api/playlist/* (panneau Super+P)

**Panneau consommateur** : [[20-Composants/pl/main-qml]] via [[20-Composants/pl/pl-sh]] — `open_panel()` relance pl.sh avec la signature Hyprland reconstruite

**MPD** : [[20-Composants/mpd/mpd-conf]] — `music_directory` ~/songs (racine lisible par MPD)

**État** : `~/.config/settings/playlist_folder` (fichier séparé de [[20-Composants/settings/settings-json]])
