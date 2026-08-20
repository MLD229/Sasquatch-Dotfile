---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# rofi

## Rattachements

**Fichiers du composant** :
- [[20-Composants/rofi/readme-md]] — documentation
- [[20-Composants/rofi/scripts/launcher-sh]] — lanceur d'applications (drun)
- [[20-Composants/rofi/scripts/icon-gen-sh]] — générateur d'icônes depuis les .desktop
- [[20-Composants/rofi/scripts/powermenu-sh]] — menu alimentation
- [[20-Composants/rofi/themes/sasquatch-rasi]] — thème principal
- [[20-Composants/rofi/themes/colors-rasi]] — palette (réécrite par theme-apply)
- [[20-Composants/rofi/themes/osd-rasi]] — thème OSD volume/luminosité

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — Super = launcher (toggle), Super+, = aide-mémoire, Super+Échap = powermenu
- [[20-Composants/scripts/clipboard-sh]], [[20-Composants/scripts/calc-sh]], [[20-Composants/scripts/keybinds-reminder-sh]] — menus rofi (thème sasquatch.rasi)
- [[20-Composants/scripts/osd-sh]] — OSD rofi (thème osd.rasi)
- [[20-Composants/waybar/config]] — presse-papier au clic (rofi + sasquatch.rasi)
- [[20-Composants/scripts/theme-apply-py]] — réécrit colors.rasi (bloc SASQUATCH-PALETTE)
- [[10-Fondations/install]] — symlink ~/.config/rofi + chmod des scripts
