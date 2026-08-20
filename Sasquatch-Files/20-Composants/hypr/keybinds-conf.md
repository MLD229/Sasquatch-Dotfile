---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/keybinds.conf

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/hypr/keybinds-user-conf]] — `source =` en fin de fichier (overrides, dernier gagnant)
- [[20-Composants/hypr/hyprlock-conf]] — `$mod+L` → hyprlock
- [[20-Composants/hypr/scripts/media-ctl-sh]] — bindl XF86AudioPlay/Next/Prev (toggle/next/prev)
- [[20-Composants/hypr/scripts/scroll-workspace-sh]] — binds commentés (blocage 1..10 ; r±1 natif actif)
- [[20-Composants/wp/wp-sh]] — `$mod+Y` sélecteur de fonds
- [[20-Composants/pl/pl-sh]] — `$mod+P` gestionnaire de playlist
- [[20-Composants/cc/cc-sh]] — `$mod+G` Control Center
- [[20-Composants/settings/settings-sh]] — `$mod+I` panneau Settings
- [[20-Composants/aiko/aiko-sh]] — `$mod+N` sidebar 愛子
- [[20-Composants/scripts/clipboard-sh]] · [[20-Composants/scripts/calc-sh]] · [[20-Composants/scripts/waybar-toggle-sh]] · [[20-Composants/scripts/volume-sh]] · [[20-Composants/scripts/brightness-sh]] · [[20-Composants/scripts/screenshot-sh]] · [[20-Composants/scripts/bluetooth-manager-sh]] · [[20-Composants/scripts/keybinds-reminder-sh]] — binds `~/.config/scripts/…`
- [[20-Composants/rofi/scripts/launcher-sh]] — bindr SUPER (launcher rofi, toggle)
- [[20-Composants/rofi/scripts/powermenu-sh]] — `$mod+Escape`
- [[20-Composants/cc/browser-bridge/manifest-json]] — `brave --load-extension=~/.config/cc/browser-bridge`

**Référencé par** :
- [[20-Composants/hypr/hyprland-conf]] — `source = ~/.config/hypr/keybinds.conf`
- [[20-Composants/settings/settings-py]] — parse ce fichier pour le panneau RACCOURCIS
- [[20-Composants/hypr/keybinds-user-conf]] — surcharge ses binds (dernier gagnant)
