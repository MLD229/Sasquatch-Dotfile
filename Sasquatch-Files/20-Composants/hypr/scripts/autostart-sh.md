---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# hypr/scripts/autostart.sh

## Rattachements

**Composant parent** : [[20-Composants/hypr]]

**Référence / source** :
- [[20-Composants/hypr/scripts/cleanup-orphans-sh]] — purge des orphelins de session en tête
- [[20-Composants/hypr/scripts/wallpaper-sh]] — restauration du wallpaper au login
- [[20-Composants/waybar/scripts/wallclock-ja-py]] — horloge hiragana en fond (`python3 … &`)
- [[20-Composants/hypr/hypridle-conf]] — `hypridle &` (idle + lock au capot)
- [[20-Composants/mako/config]] — `mako &` (notifications)
- [[20-Composants/fcitx5]] — `fcitx5 -d &` (IME mozc)
- [[20-Composants/mpd/mpd-conf]] — `systemctl --user start mpd` + `mpc clear` (filet de sécurité)
- [[20-Composants/cc/sasquatch-cc-service]] — `import-environment` + restart du service backend CC
- [[20-Composants/scripts/theme-apply-sh]] — appel direct en filet de sécurité (flock)

**Référencé par** :
- [[20-Composants/hypr/hyprland-conf]] — `exec-once = ~/.config/hypr/scripts/autostart.sh`
