---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# subpage/state.py

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Utilisé par** :
- [[20-Composants/subpage/shell-qml]] — `state.py --watch` (ligne « open <moniteur> » / « closed »)
- [[20-Composants/subpage/subpage-sh]] — `state.py --check` (exit 0 = page ouverte)

**Rôle** : **source de vérité unique** de l'état de la sub page. Lit
`hyprctl monitors -j` et cherche `monitor.specialWorkspace.name ==
"special:subpage"`.

⚠️ Ne JAMAIS utiliser `hyprctl activeworkspace` pour ça : il renvoie le
workspace du moniteur (いち, に, …) et jamais le special — il ne dit donc rien
sur la page.

**Modes** :
- `--check` → exit 0 si ouverte, 1 sinon (muet)
- `--monitor` → nom du moniteur qui l'affiche
- `--json` → `{"open": bool, "monitor": "eDP-1"|null}`
- `--watch [--interval 0.15]` → reste vivant, imprime une ligne **par changement**

**Mise en œuvre** : une requête `j/monitors` sur la socket de commande de
Hyprland (`$XDG_RUNTIME_DIR/hypr/<sig>/.socket.sock`), repli sur
`hyprctl monitors -j`. Aucun état stocké sur disque : l'état est relu à chaque
interrogation, donc il reste juste même si la page est fermée par un autre
biais (autre keybind, `hyprctl dispatch` à la main).
