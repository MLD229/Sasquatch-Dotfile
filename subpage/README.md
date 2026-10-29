# subpage — sub page (scratchpad) Sasquatch

`Super+S` ouvre/ferme la page, `Super+Alt+S` y envoie la fenêtre active.

La page est un **special workspace Hyprland** (`special:subpage`) : les apps
qu'on y met restent vivantes (cachées) quand la page est fermée.

## Fichiers

| fichier | rôle |
|---|---|
| `shell.qml` | décoration : surface **layer-shell** Quickshell (4 coins en L + étiquette サブページ). Pas une fenêtre. |
| `state.py` | source de vérité « la page est-elle ouverte ? » (`hyprctl monitors -j`) |
| `subpage.sh` | toggle (`toggle` / `open` / `close` / `status`) |
| `send.sh` | envoie la fenêtre active dans la page |
| `tests/verify.sh` | preuves scriptées (lint, netteté, focus, layers, synchronisation) |
| `_archive/` | ancienne version (fenêtre plein écran `main.qml`) — ne plus utiliser |

## Architecture (v2, 2026-10-29)

La décoration n'est **pas une fenêtre** : c'est une surface layer-shell
(`PanelWindow`, namespace `subpage`, layer `top`, `exclusiveZone: 0`,
`keyboardFocus: None`). Conséquences :

- elle ne vit pas dans le workspace → **aucune windowrule**, aucun piège
  d'ordre d'ouverture, aucun `alterzorder` ;
- aucun blur demandé → **aucun voile flou** ;
- aucun focus clavier → **aucun vol de focus** ; `Échap` ne peut pas fermer la
  page (**fermeture = Super+S**) ;
- la région d'entrée (`mask`) ne couvre que les traits et l'étiquette : le
  centre de l'écran laisse 100 % passer la souris.

Pourquoi un layer `top` et pas `background` : mesuré, une surface
background/bottom est **invisible sous l'overlay du special workspace**
(Hyprland dessine la sub page au-dessus du plan des fenêtres). En `top`, une
fenêtre vraiment plein écran (jeu) recouvre la décoration — comportement voulu ;
et la surface n'existe pas quand la page est fermée.

Visibilité : `state.py --watch` interroge Hyprland toutes les 150 ms. Fermer la
page autrement qu'avec le script fait disparaître la décoration en ~150 ms ;
5 s après fermeture, le process quickshell s'arrête seul.

## Tester

```sh
~/.config/subpage/tests/verify.sh      # captures + sorties dans tests/out/
```

Le script travaille sur un workspace de test vide et restaure le workspace de
l'utilisateur à la fin.

## Non couvert par les tests

Souris réelle sur les traits, jeu en plein écran, multi-écrans.
