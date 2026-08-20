---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# waybar/scripts/fastview.py

## Rattachements

**Composant parent** : [[20-Composants/waybar]]

**Lancé par** :
- [[20-Composants/waybar/config]] — module invisible `custom/fastview` (exec python3, format vide)

**Lit** :
- [[20-Composants/waybar/style-css]] — bloc SASQUATCH-PALETTE (palette du popup) ; constantes alignées sur #workspaces (margin 6, padding 4, min-width 24)
- [[20-Composants/hypr/conf.d/rules-conf]] — `defaultName` いち…じゅう = WS_LABELS (mesure des largeurs de boutons)
- [[20-Composants/hypr]] — IPC hyprctl (clients, monitors, layers, cursorpos) ; popup layer-shell OVERLAY sous la barre

**Dépendances** : grim (capture du workspace actif), gtk-layer-shell + PangoCairo (daemon GTK3)
