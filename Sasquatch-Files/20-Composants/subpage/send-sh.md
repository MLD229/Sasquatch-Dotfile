---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-20
---

# subpage/send.sh

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Lancé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod ALT, S, exec, ~/.config/subpage/send.sh` (Super+Alt+S : envoyer la fenêtre courante DANS la sub page)

**Lance / contrôle** :
- [[20-Composants/subpage/main-qml]] — lance le cadre Quickshell si absent (page fermée, mapping safe)
- Hyprland : `hyprctl dispatch movetoworkspace special:subpage` (déplace la fenêtre active dans le scratchpad) + `togglespecialworkspace subpage` (ouvre la page si elle était fermée)

**Garde-fous** : ne bouge ni le cadre (`Sasquatch Subpage`) ni une fenêtre déjà dans `special:subpage`.

**Ordre critique** (identique à [[20-Composants/subpage/subpage-sh]]) : ne JAMAIS mapper le cadre quand le special est OUVERT (le mapping le FERME). Page ouverte + cadre absent → bouger direct, sans lancer le cadre.

**Installation** :
- [[10-Fondations/install]] — `chmod +x subpage/*.sh`
