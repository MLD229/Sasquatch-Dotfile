---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# waybar/waybar.service

## Rattachements

**Composant parent** : [[20-Composants/waybar]]

**Lance** :
- [[20-Composants/waybar/config]] et [[20-Composants/waybar/style-css]] — ExecStart=/usr/bin/waybar charge config + thème

**Référencé par** :
- [[20-Composants/scripts/theme-apply-sh]] — systemctl --user reload/start waybar (SIGUSR2 = nouvelle palette, Restart=on-failure)
- [[20-Composants/scripts/waybar-toggle-sh]] — SIGUSR1 : toggle visible/invisible sur le process supervisé
- [[10-Fondations/install]] — install.sh lie waybar.service vers le user manager systemd
