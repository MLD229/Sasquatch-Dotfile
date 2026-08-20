---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# themes

## Rattachements

**Fichiers du composant** :
- [[20-Composants/themes/gtk/gtk-3.0/gtk-css]] — styles GTK3 (icônes symboliques, fond sombre)
- [[20-Composants/themes/gtk/gtk-3.0/settings-ini]] — thème Catppuccin Mocha + Papirus-Dark
- [[20-Composants/themes/gtk/gtk-4.0/gtk-css]] — importe le gtk.css GTK3
- [[20-Composants/themes/gtk/gtk-4.0/settings-ini]] — même thème que GTK3
- [[20-Composants/themes/qt/kdeglobals]] — couleurs et thème des apps Qt

**Référencé par** :
- [[20-Composants/hypr/conf.d/env-conf]] — `GTK_THEME=catppuccin-mocha-blue-standard+default` (même thème que les settings.ini) et `QT_QPA_PLATFORMTHEME=qt5ct` (apps Qt)
- [[10-Fondations/install]] — symlinks individuels : ~/.config/gtk-3.0, ~/.config/gtk-4.0, ~/.config/kdeglobals
- [[10-Fondations/symlinks]] — gtk-3.0, gtk-4.0 et kdeglobals pointent vers le repo

Note : PAS touché par theme-apply.py (aucun bloc SASQUATCH-PALETTE) — thème fixe Catppuccin, contrairement à rofi/mako/kitty/fastfetch.
