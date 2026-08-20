---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# cc

## Rattachements

**Fondations** :
- [[10-Fondations/symlinks]] — `~/.config/cc/` pointe vers ce dossier (symlink)
- [[10-Fondations/theme-dynamique]] — palette suivie en direct (Palette.qml régénérée par theme-apply.py)

**Backend Python (service systemd permanent)** :
- [[20-Composants/cc/server-py]] — serveur HTTP 127.0.0.1:8765, point d'entrée du service
- [[20-Composants/cc/config-py]] — constantes partagées (fifos, socket MPD, token bridge)
- [[20-Composants/cc/metrics-py]] · [[20-Composants/cc/viz-py]] · [[20-Composants/cc/mpd-py]] · [[20-Composants/cc/player-py]] · [[20-Composants/cc/actions-py]] · [[20-Composants/cc/cava-py]] · [[20-Composants/cc/palette-py]] · [[20-Composants/cc/wallpaper-py]] · [[20-Composants/cc/playlist-py]] · [[20-Composants/cc/translate-py]] · [[20-Composants/cc/web_bridge-py]]

**Scripts** :
- [[20-Composants/cc/cc-sh]] — toggle fenêtre + démarrage du service
- [[20-Composants/cc/ocr-sh]] — sélection → grim → tesseract
- [[20-Composants/cc/apply-wallpaper-sh]] — hyprpaper + palette

**Service** :
- [[20-Composants/cc/sasquatch-cc-service]] — unit systemd user

**Frontend Quickshell** :
- [[20-Composants/cc/main-qml]] — fenêtre « Sasquatch CC »
- [[20-Composants/cc/qml/gauge-qml]] · [[20-Composants/cc/qml/iconbutton-qml]] · [[20-Composants/cc/qml/sparkline-qml]] · [[20-Composants/cc/qml/tile-qml]] (+ Palette.qml, régénéré par theme-apply.py)

**Extension navigateur MV3 (pont now-playing)** :
- [[20-Composants/cc/browser-bridge/background-js]] · [[20-Composants/cc/browser-bridge/content-js]] · [[20-Composants/cc/browser-bridge/manifest-json]]

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, G, exec, ~/.config/cc/cc.sh`
- [[20-Composants/hypr/conf.d/rules-conf]] — windowrules de la fenêtre « Sasquatch CC »
- [[20-Composants/hypr/scripts/autostart-sh]] — restart du service au login
- [[20-Composants/wp/wp-sh]] · [[20-Composants/pl/pl-sh]] — consomment l'API du serveur
- [[20-Composants/scripts/screenshot-sh]] — ferme la fenêtre CC pendant la capture
- [[10-Fondations/install]] — installe le service user + symlinks
