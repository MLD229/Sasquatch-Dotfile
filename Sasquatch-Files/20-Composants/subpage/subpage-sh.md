---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# subpage/subpage.sh

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Déclenché par** :
- [[20-Composants/hypr/keybinds-conf]] — `bind = $mod, S, exec, ~/.config/subpage/subpage.sh` (Super+S)

**Utilise** :
- [[20-Composants/subpage/state-py]] — `--check` (page ouverte ?) et `--monitor`
- [[20-Composants/subpage/shell-qml]] — lance/arrête la décoration (`quickshell -n -p shell.qml`)

**Usage** : `subpage.sh [toggle|open|close|status]` (défaut `toggle`)

**Logique** :
- page ouverte → `hyprctl dispatch togglespecialworkspace subpage` (ferme) puis
  arrêt de la décoration (la surface disparaît aussi d'elle-même via la synchro)
- page fermée → démarre la décoration si absente, PUIS ouvre la page. **L'ordre
  n'a plus d'importance** : la décoration n'est pas mappée dans le workspace,
  donc mapper/ouvrir dans n'importe quel ordre ne ferme plus la page (c'était
  les 40 lignes de précautions de l'ancienne version)
- une seule instance : détection par argv exact (`/proc/*/cmdline` == chemin de
  `shell.qml`), lancement avec `quickshell -n` (--no-duplicate)

**Fragile / à savoir** : `open` attend que la surface apparaisse dans
`hyprctl layers` (max 3 s) et sort en erreur si ce n'est pas le cas (log :
`$XDG_RUNTIME_DIR/subpage/decoration.log`). Les scripts reconstituent
`HYPRLAND_INSTANCE_SIGNATURE` si l'environnement ne la fournit pas.
