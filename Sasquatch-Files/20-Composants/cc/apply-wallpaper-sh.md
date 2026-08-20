---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/apply-wallpaper.sh

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Appelé par** :
- [[20-Composants/cc/wallpaper-py]] — `apply_wallpaper()` (backend, /api/wallpaper/apply)
- [[20-Composants/hypr/scripts/wallpaper-sh]] — restauration au login (même chaîne)

**Relance** : hyprpaper + IPC `hyprctl hyprpaper` (cf. [[20-Composants/hypr/hyprpaper-conf]])

**Palette** : lance [[20-Composants/scripts/theme-apply-sh]] en fire-and-forget (flock sérialisé)

**État** : `~/.config/waypaper/config.ini` (restauration sans argument)

**Environnement** : détecte WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE (le service systemd n'en a pas — [[20-Composants/cc/sasquatch-cc-service]])
