---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-20
---

# subpage/subpage.sh

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, S, exec, ~/.config/subpage/subpage.sh` (Super+S)

**Lance / contrôle** :
- [[20-Composants/subpage/main-qml]] — cadre Quickshell (toggle ON) / `closewindow` (toggle OFF)
- Hyprland : `hyprctl dispatch togglespecialworkspace subpage` (scratchpad natif)

**Pattern** : toggle launcher (comme [[20-Composants/wp/wp-sh]] et [[20-Composants/settings/settings-sh]]) — `window_open()` parse `hyprctl clients -j` en Python ; détection du special workspace via `hyprctl activeworkspace -j | grep '"name": "special:subpage"'`.

**Installation** :
- [[10-Fondations/install]] — `chmod +x subpage/*.sh`
