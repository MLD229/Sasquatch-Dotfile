---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# wp/main.qml

## Rattachements

**Composant parent** : [[20-Composants/wp]]

**Backend (serveur CC, 127.0.0.1:8765)** :
- [[20-Composants/cc/server-py]] — serveur HTTP
- [[20-Composants/cc/wallpaper-py]] — /api/wallpapers, /api/wallpaper/pick, /api/wallpaper/folder, /api/wallpaper/apply, /api/wallpaper/random, /api/wallpaper/thumb, /api/palette

**Composant importé (`import "qml"`)** :
- [[20-Composants/wp/qml/wpbutton-qml]] — Dossier…, Fichier…, ‹ ›, 🎲, Appliquer, ✕

**Pipeline d'application** :
- [[20-Composants/cc/apply-wallpaper-sh]] — config.ini → hyprpaper
- [[20-Composants/scripts/theme-apply-sh]] — palette suit (waybar, kitty, fastfetch, CC, overlays)
- [[20-Composants/hypr/scripts/wallpaper-sh]] — restauration au login (script commun)

**Config lue** : `~/.config/waypaper/config.ini` (`folder=` = souvenir du dossier affiché au lancement)
