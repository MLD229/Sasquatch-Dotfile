---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# scripts/waybar-toggle.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : `pgrep -x waybar`, `kill -USR1` (toggle natif waybar), lecture `/proc/<pid>/environ` (signature d'instance)

**Références** :
- [[20-Composants/scripts/theme-apply-sh]] — même logique `waybar_current_session()` (anti-orphelin)
- [[20-Composants/waybar/waybar-service]] — processus supervisé par le service

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, J`
- [[20-Composants/waybar]] — toggle visible/invisible de la barre
