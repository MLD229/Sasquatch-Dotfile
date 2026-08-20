---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# scripts/bluetooth-manager.sh

## Rattachements

**Composant parent** : [[20-Composants/scripts]]

**Appels** : `pgrep`/`pkill`/lancement de `blueman-manager` (retry 5× anti-crash scan BLE)

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = SUPER, b, exec, ~/.config/scripts/bluetooth-manager.sh`
- [[20-Composants/scripts/bluetooth-sh]] — mentionne que Super+B passe par ce script (CLI dédiée)
- [[10-Fondations/requirements]] — bluez, bluez-utils, blueman
