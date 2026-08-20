---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-19
---

# settings/main.qml

## Rattachements

**Composant parent** : [[20-Composants/settings]]

**Backend** :
- [[20-Composants/settings/settings-py]] — API http://127.0.0.1:8770 (/api/state, /api/palette, /api/system, /api/keybinds, /api/veille, /api/clock, /api/cc, /api/wallpaper, /api/close)

**Composants importés (`import "qml"`)** :
- [[20-Composants/settings/qml/section-qml]] — 6 sections (veille, apparence, horloge, raccourcis, control panel, système)
- [[20-Composants/settings/qml/toggle-qml]], [[20-Composants/settings/qml/sliderrow-qml]]
- [[20-Composants/settings/qml/colorswatch-qml]], [[20-Composants/settings/qml/fieldrow-qml]]
- [[20-Composants/settings/qml/keybindrow-qml]]

**Style calqué sur** :
- [[20-Composants/cc/main-qml]] — FloatingWindow plein écran, palette pollée toutes les 2 s, api() XHR inline

**Palette** : /api/palette ← `cc/qml/Palette.qml` (via settings.py, voir [[20-Composants/scripts/theme-apply-py]])

**Bouton « Choisir un wallpaper »** : POST /api/wallpaper → settings.py lance waypaper (outil remplacé par [[20-Composants/wp]])
