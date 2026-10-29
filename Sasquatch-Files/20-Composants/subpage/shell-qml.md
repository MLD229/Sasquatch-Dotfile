---
tags: [sasquatch-files, fichiers]
type: fichier
updated: 2026-10-29
---

# subpage/shell.qml

## Rattachements

**Composant parent** : [[20-Composants/subpage]]

**Lancé par** :
- [[20-Composants/subpage/subpage-sh]] — `quickshell -n -p shell.qml` (une seule instance)

**Dépend de** :
- [[20-Composants/subpage/state-py]] — `state.py --watch` (Process + SplitParser)
- `~/.config/cc/qml/Palette.qml` — palette du thème (FileView + watchChanges), repli `#066678` / `#6a8388`

**Rôle** : décoration de la sub page. `PanelWindow` Quickshell =
**surface layer-shell**, pas une fenêtre : `WlrLayershell.layer: Top`,
`namespace: "subpage"`, `keyboardFocus: None`, `exclusiveZone: 0`,
`focusable: false`, `color: "transparent"`. Aucune windowrule Hyprland ne
s'applique (cf. [[20-Composants/hypr/conf.d/rules-conf]]).

**Dessin (v2.2)** : une étiquette `サブページ` seule, dans la gouttière du haut
(`gapsout:16`), jamais sur le contenu d'une app. **Ni coins, ni voile, ni aucun
rectangle coloré** : la page ne peint plus de fond et n'assombrit plus le
bureau (`dim_special = 0`, cf. [[20-Composants/hypr/conf.d/decoration-conf]]).
Le seul `Rectangle` restant est transparent : il sert uniquement de géométrie
au `mask`.

**Région d'entrée** : `mask: Region { item: veil }` = surface entière → une
page vide capte les clics (sinon un clic au centre tombait sur le bureau
caché). Le clic est absorbé, pas volé : aucun grab clavier
(`WlrKeyboardFocus.None`), Échap ne peut PAS fermer la page, c'est Super+S.

**Synchronisation** : `visible: specialOpen`, alimenté par `state.py --watch`
(polling 150 ms sur `hyprctl monitors -j`). Fermer la page autrement qu'avec le
script fait disparaître la décoration en ~150 ms ; après 5 s page fermée, le
process s'arrête de lui-même (pas de process résident).

**Limite connue** : pas de `pragma ComponentBehavior: Bound` — il fait planter
`qmllint` (Qt 6.10, rc=255 sans message) alors que le fichier se vérifie
normalement sans lui.
