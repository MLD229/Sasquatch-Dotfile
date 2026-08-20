---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-08-20
---

# subpage/main.qml

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Lancé par** :
- [[20-Composants/subpage/subpage-sh]] — `quickshell -p main.qml` (toggle ON)

**Windowrules** :
- [[20-Composants/hypr/conf.d/rules-conf]] — `match:title ^(Sasquatch Subpage)$` : workspace special:subpage silent, float 100% 100%, border_size 0, noinitialfocus, ignorezorder

**Rôle** : cadre décoratif plein écran TRANSPARENT (FloatingWindow, `color: "transparent"`) avec contour arrondi (Rectangle radius 26, border accent Catppuccin #89b4fa) + étiquette « サブページ ». La transparence laisse voir le wallpaper ; les apps du special workspace s'affichent par-dessus.

**Palette** : couleurs fixes Catppuccin Mocha (fallback). Pour suivre la palette dynamique : poller `/api/palette` comme [[20-Composants/wp/main-qml]].
