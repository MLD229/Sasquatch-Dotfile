# BRIEF Rin — SUB PAGE v2 : refonte à zéro (layer-shell, plus de fenêtre cadre)

Date : 2026-10-29
Auteur : Asuka — demande de momo (« refaire à zéro car là ça marche pas »)
Destinataire : Rin

## CE QUI EXISTE ET POURQUOI ÇA CASSE (diagnostic réel, vérifié aujourd'hui)

`subpage/` = scratchpad Hyprland : `Super+S` →
`hyprctl dispatch togglespecialworkspace subpage`. Un cadre décoratif
(`main.qml`, FloatingWindow plein écran 1920×1038) est mappé DANS le special
workspace via `windowrule ... workspace special:subpage silent`.

Pannes observées à l'écran (captures) :
1. **Aucune règle `noblur`** sur cette fenêtre → Hyprland floute toute la
   surface de la fenêtre transparente → **l'écran entier est flou**, les apps
   du scratchpad sont illisibles.
2. Les coins s'affichent en **petits carrés flous** au lieu de traits fins.
3. Il faut `alterzorder bottom` à la main sinon le cadre passe **au-dessus**
   des apps (elles deviennent invisibles / non cliquables).
4. Piège structurel : mapper une fenêtre avec cette windowrule **pendant que
   le special est ouvert le FERME**. D'où un `subpage.sh` plein de cas
   particuliers (attente du mapping réel, ordre des toggles…), fragile.
5. `no_focus on` mais des clics se perdent quand même.

**Verdict : l'architecture « fenêtre décorative dans le workspace » est le
problème.** On la supprime.

## ARCHITECTURE v2 (décidée, consultation ChatGPT + Hyprland 0.56.2)

**Le cadre devient une surface layer-shell de FOND (`Layer.background`),
jamais une fenêtre Hyprland.** Conséquences directes :
- elle ne vit PAS dans le special workspace → **plus aucun piège de mapping**,
  plus d'`alterzorder`, plus d'attente de mapping ;
- pas de flou (on ne demande aucun blur) et pas de vol de focus ;
- les apps du scratchpad se dessinent **au-dessus** d'elle par construction.

Nouveaux fichiers (remplacent les anciens, `main.qml` va dans `_archive/`) :

```
subpage/
  shell.qml      PanelWindow layer=background, exclusiveZone 0, focus none
                 → 4 coins en L + étiquette サブページ, palette du thème
                 → visible SEULEMENT quand special:subpage est ouvert
  state.py       helper partagé : « la subpage est-elle ouverte ? »
                 source de vérité UNIQUE : hyprctl monitors -j
                 → specialWorkspace.name == "special:subpage" (jamais activeworkspace)
  subpage.sh     toggle : ouvre/ferme le special + lance/arrête la décoration
  send.sh        envoie la fenêtre active dans la subpage (Super+ALT+S)
  tests/         preuves scriptées (voir §VÉRIFICATION)
```

### Détection d'état
- `hyprctl monitors -j` → un moniteur a `specialWorkspace.name == "special:subpage"`.
- `shell.qml` doit suivre l'état **en continu** (polling léger 150–250 ms OU
  événements `Quickshell.Hyprland` si tu les maîtrises) : si l'utilisateur ferme
  la page autrement (autre keybind, `hyprctl dispatch`), la décoration doit
  disparaître **sans clignotement**.
- Aucun état stocké sur disque : tout est dérivé de Hyprland.

### `subpage.sh` (Super+S)
- ouvert → `togglespecialworkspace subpage` (ferme) ; la décoration se cache
  d'elle-même via la synchro.
- fermé → démarrer la décoration si absente, PUIS `togglespecialworkspace subpage`.
  Comme la décoration n'est plus mappée dans le workspace, **l'ordre n'a plus
  d'importance** : dis-le en commentaire (ça remplace les 40 lignes de
  précautions de l'ancienne version).
- Une seule instance de décoration (vérifier par `quickshell` pid/namespace
  `subpage`, pas par pgrep approximatif).
- Idempotent, `set -uo pipefail`, jamais de `|| true` qui masque une erreur.

### `send.sh` (Super+ALT+S)
- fenêtre active → `movetoworkspacesilent special:subpage,address:<addr>`
- si la page est fermée : l'ouvrir d'abord (elle reste ouverte après, c'est
  voulu) ; si aucune fenêtre active : message clair, rien d'autre.
- Restaurer le focus sur la fenêtre envoyée est inutile (elle part dans le
  scratchpad) — ne vole pas le focus.

### Visuel (cohérence avec le reste du dotfile)
- Palette : lire `~/.config/cc/qml/Palette.qml` (générée par `theme-apply.py`)
  → même accent, même style que `cc/sidebar` et `aiko` : coins en L de 3 px,
  bras ~56 px, marge 10 px, étiquette `サブページ` discrète (opacité ~0.7).
- **Aucun remplissage plein écran** (pas de Rectangle de fond) : uniquement les
  8 traits + l'étiquette. Un fond, même très transparent, refait le bug du flou.
- **Clics** : la région d'entrée doit être limitée aux traits + étiquette
  (`mask` / `Region`), le centre laisse 100 % passer la souris.
- **Focus** : `WlrLayershell.keyboardFocus: None`, `exclusiveZone: 0`,
  `layer: WlrLayer.Background`. Aucun grab clavier (la leçon hyprlock).
- Échap ne peut PAS fermer (pas de focus clavier) : documenter que la
  fermeture = Super+S.

### Nettoyage obligatoire
- Supprimer dans `hypr/conf.d/rules.conf` la windowrule du cadre :
  `windowrule = match:title ^(Sasquatch Subpage)$, workspace special:subpage silent`
  ainsi que `float on/size/move/no_focus` qui la concernent. **Garder**
  `workspace = special:subpage, gapsout:16, gapsin:6` (ou ajuster).
- Si tu gardes un `blur` côté layerrule : ne le mets PAS sur le namespace
  subpage.
- `main.qml` → `subpage/_archive/`. `send.sh`/`subpage.sh` réécrits.
- Mettre à jour `hypr/keybinds.conf` si les chemins changent (garder Super+S et
  Super+ALT+S), et `install.sh` (copie `subpage/` → `~/.config/subpage/`).

## VÉRIFICATION (preuves réelles, session Hyprland dispo)
Env : `XDG_RUNTIME_DIR=/run/user/1000`, `WAYLAND_DISPLAY=wayland-1`,
`HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)`, `DISPLAY=:0`.

1. `qmllint` sur `shell.qml` (si 255 sans message : documente la limite) +
   `python3 -m py_compile state.py` + `bash -n` sur les 2 scripts.
2. **Ouverture** : `subpage.sh` → `hyprctl monitors -j` montre
   `special:subpage`, et `hyprctl layers` montre le layer `subpage` en
   `background`. Colle les deux sorties.
3. **Aucun flou** : capture `grim` → vérifie que le contenu du scratchpad est
   NET (compare une capture avec une fenêtre dedans). Regarde l'image.
4. **Fenêtre dedans visible et cliquable** : envoie une fenêtre
   (`send.sh` ou `movetoworkspacesilent`) et prouve que le cadre est DERRIÈRE
   (`hyprctl layers` + capture nette, PAS de `alterzorder`).
5. **Clics au centre** : la région d'entrée ne couvre que les coins
   (le prouver par le code + capture ; au clavier/souris réel, dis ce qui n'a
   pas pu être testé).
6. **Fermeture** : `subpage.sh` → special absent + décoration disparue
   (`hyprctl layers` vide pour ce namespace) + aucune régression des fenêtres
   (elles restent dans le scratchpad, cache).
7. **Synchronisation** : fermer par `hyprctl dispatch togglespecialworkspace subpage`
   directement (sans passer par le script) → la décoration doit disparaître
   seule. Colle le résultat.
8. **Pas de focus volé** : la fenêtre active avant/après `subpage.sh` doit être
   la même (`hyprctl activewindow -j`).
9. `main.qml` du scratchpad ne doit plus être référencé nulle part
   (`grep -rn "subpage/main.qml"`).

## RÈGLES
- Repartir de zéro pour `subpage/` (l'ancien est archivé), ne pas toucher
  `cc/sidebar` ni `aiko`.
- Pas de commit (momo valide).
- Sois honnête sur ce qui n'a pas pu être testé (souris réelle, jeu en
  plein écran, fermeture par un autre biais).
- momo joue parfois en plein écran : la décoration ne doit JAMAIS apparaître
  au-dessus d'un jeu ni voler le focus.

## LIVRABLE
Fichiers, sorties `hyprctl` réelles, captures regardées, une ligne par panne
corrigée, ce qui reste fragile.
