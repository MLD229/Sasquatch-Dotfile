---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-20
---

# subpage

## Rattachements

**Fichiers du composant** :
- [[20-Composants/subpage/main-qml]] — cadre décoratif Quickshell (transparent, contour arrondi)
- [[20-Composants/subpage/subpage-sh]] — toggle launcher (Super+S)

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, S, exec, ~/.config/subpage/subpage.sh` (Super+S ; movefocus d libéré pour ça)

**Concept — scratchpad Hyprland (special workspace)** :
- [[20-Composants/hypr/conf.d/rules-conf]] — windowrules du cadre : `workspace special:subpage silent`, float 100%, noinitialfocus, ignorezorder
- Le toggle utilise `hyprctl dispatch togglespecialworkspace subpage` (pas de script custom côté serveur)

**Installation** :
- [[10-Fondations/symlinks]] — `~/.config/subpage` → repo (ajouté install.sh)
- [[10-Fondations/install]] — `chmod +x subpage/*.sh`

**Note** : les apps lancées pendant que la page est active s'ouvrent dans le special workspace (workspace actif) — pas de windowrule de classe nécessaire. Le hide (re-Super+S) cache le workspace mais les apps restent ouvertes.
