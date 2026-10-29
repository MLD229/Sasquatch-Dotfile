---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# subpage/send.sh

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Déclenché par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod ALT, S, exec, ~/.config/subpage/send.sh` (Super+Alt+S)

**Utilise** :
- [[20-Composants/subpage/subpage-sh]] — `status` (page ouverte ?) et `open`
- Hyprland : `hyprctl dispatch movetoworkspacesilent special:subpage,address:<addr>`

**Rôle** : envoie la **fenêtre active** dans la sub page, sans changer de
workspace visible (`movetoworkspacesilent`). Si la page est fermée, elle est
ouverte d'abord et **reste ouverte** (voulu : on veut voir ce qu'on vient
d'envoyer). Aucune fenêtre active → message clair sur stderr, rien d'autre.

**Garde-fous** : refuse d'envoyer une fenêtre déjà dans `special:subpage`.

**Aucun vol de focus** : on ne rappelle jamais la fenêtre envoyée (elle part
dans le scratchpad) et on ne touche pas au focus du workspace courant ; plus
d'`alterzorder`, plus d'ordre de mapping (la décoration n'est pas une fenêtre).
