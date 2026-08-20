---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# pl

## Rattachements

**Fichiers du composant** :
- [[20-Composants/pl/main-qml]] — panneau « Sasquatch Playlist »
- [[20-Composants/pl/pl-sh]] — toggle launcher (Super+P)
- [[20-Composants/pl/qml/plbutton-qml]] — bouton
- [[20-Composants/pl/qml/pllibrow-qml]] — ligne de résultat de recherche
- [[20-Composants/pl/qml/plrow-qml]] — ligne de la playlist courante

**Backend (pilote le MPD)** :
- [[20-Composants/cc/server-py]] — routes /api/playlist/* sur 127.0.0.1:8765
- [[20-Composants/cc/playlist-py]] — module playlist (MPD, bibliothèque ~/songs)

**Lancé ici** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, p, exec, ~/.config/pl/pl.sh` (Super+P)
- [[20-Composants/cc/main-qml]] — bouton 📃 → POST /api/playlist/open → pl/pl.sh

**Référencé par** :
- [[10-Fondations/install]] — symlink `~/.config/pl` → repo, chmod pl/*.sh
- [[00-Index]]
