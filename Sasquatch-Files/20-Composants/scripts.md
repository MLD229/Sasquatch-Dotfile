---
tags: [sasquatch-files, composants]
type: composant
updated: 2026-08-19
---

# scripts

## Rattachements

**Composant parent** : (aucun — racine du composant)

**Fichiers du composant** :
- [[20-Composants/scripts/bluetooth-manager-sh]] — toggle blueman-manager (Super+B, wrapper anti-crash scan BLE)
- [[20-Composants/scripts/bluetooth-sh]] — Bluetooth CLI (bluetoothctl, non bindé)
- [[20-Composants/scripts/brightness-sh]] — luminosité (brightnessctl) + OSD
- [[20-Composants/scripts/calc-sh]] — calculatrice rofi live (qalc, Super+C)
- [[20-Composants/scripts/clipboard-sh]] — presse-papier (cliphist + rofi, Super+V)
- [[20-Composants/scripts/fix-suspend-sh]] — veille NVIDIA (GRUB modeset, sudo manuel)
- [[20-Composants/scripts/keybinds-reminder-sh]] — aide-mémoire des raccourcis (rofi, Super+,)
- [[20-Composants/scripts/osd-sh]] — OSD barre de progression (rofi)
- [[20-Composants/scripts/screenshot-sh]] — captures grim/slurp (Print / Super+Print)
- [[20-Composants/scripts/theme-apply-py]] — palette dynamique depuis le wallpaper (PIL)
- [[20-Composants/scripts/theme-apply-sh]] — point d'entrée shell du thème (flock)
- [[20-Composants/scripts/volume-sh]] — volume (wpctl) + OSD
- [[20-Composants/scripts/waybar-toggle-sh]] — bascule waybar (SIGUSR1, Super+J)
- [[20-Composants/scripts/wifi-sh]] — WiFi CLI (iwctl, non bindé)

**Fondations** :
- [[10-Fondations/symlinks]] — `scripts/` → `~/.config/scripts` (symlink)
- [[10-Fondations/install]] — liens + chmod des scripts ; paquets (libqalculate, cliphist, brightnessctl, grim, slurp, bluez…)
- [[10-Fondations/theme-dynamique]] — theme-apply.py/.sh, moteur de la palette

**Référencé par** :
- [[20-Composants/hypr/keybinds-conf]] — binds des scripts (Super+C/V/J, Print, XF86*…)
- [[20-Composants/rofi]] — thèmes sasquatch.rasi / osd.rasi utilisés par les menus
