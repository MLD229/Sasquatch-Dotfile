---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# cc/wallpaper.py

## Rattachements

**Composant parent** : [[20-Composants/cc]]

**Importe** : [[20-Composants/cc/config-py]] — RUNTIME_DIR (cache miniatures)

**Importé par** : [[20-Composants/cc/server-py]] — /api/wallpapers, /api/wallpaper/random|thumb|folder|apply|pick

**Lance** : [[20-Composants/cc/apply-wallpaper-sh]] — hyprpaper direct + [[20-Composants/scripts/theme-apply-sh]] (palette)

**État** : `~/.config/waypaper/config.ini` — clés `folder=` / `wallpaper=` (remplace waypaper)

**Sélecteur consommateur** : [[20-Composants/wp/main-qml]] via [[20-Composants/wp/wp-sh]] (Super+Y)

**Chaîne partagée avec** : [[20-Composants/hypr/scripts/wallpaper-sh]] — restauration au login
