---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# settings

## Rattachements

**Fichiers du composant** :
- [[20-Composants/settings/settings-py]] — backend HTTP (port 8770)
- [[20-Composants/settings/settings-json]] — état du panneau
- [[20-Composants/settings/settings-sh]] — toggle launcher
- [[20-Composants/settings/main-qml]] — UI Quickshell
- [[20-Composants/settings/qml/section-qml]], [[20-Composants/settings/qml/toggle-qml]], [[20-Composants/settings/qml/sliderrow-qml]]
- [[20-Composants/settings/qml/colorswatch-qml]], [[20-Composants/settings/qml/fieldrow-qml]], [[20-Composants/settings/qml/keybindrow-qml]]

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, I, exec, ~/.config/settings/settings.sh` (Super+I)

**Fichiers pilotés** :
- [[20-Composants/hypr/hypridle-conf]] — régénéré (section veille)
- [[20-Composants/hypr/keybinds-user-conf]] — overrides de raccourcis
- [[20-Composants/hypr/keybinds-conf]] — source des binds affichés
- [[20-Composants/waybar/config]] — format d'horloge patché
- [[20-Composants/hypr/conf.d/general-conf]], [[20-Composants/hypr/conf.d/decoration-conf]], [[20-Composants/hypr/conf.d/animations-conf]] — section SYSTÈME

**Relations** :
- [[20-Composants/scripts/theme-apply-sh]] — relancé après palette/horloge
- [[20-Composants/cc/server-py]] — lit settings.json (section cc)
- [[10-Fondations/symlinks]] — `~/.config/settings/` symlinké vers le repo
