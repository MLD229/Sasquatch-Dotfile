# Brief — barre Sasquatch : fond retiré + boutons de position (Gauche / Haut / Droite)

Dépôt **réel** (vérifié, c'est la cible des symlinks) :
`/home/momo/Downloads/Sasquatch-Dotfile`
- barre : `cc/bar/` (QML `shell.qml` + modules dans `cc/bar/modules/`, config `cc/bar/bar.json`,
  writer chirurgical `cc/bar/barjson.py`, tests dans `cc/bar/tests/`)
- réglages : `settings/` (backend `settings.py` port 8770, QML `settings/main.qml` + `settings/qml/`)
- palette générée : `cc/qml/Palette.qml` (ne JAMAIS la modifier, ne jamais modifier
  `scripts/theme-apply*`)

## Demande de momo (verbatim)

« enlever le fond de la sasbarre genre que les utils ? et dans son settings bien mettre des boutons
pour placer soit à droit ou en haut ou à gauche »

## Tâche 1 — plus de fond : seuls les modules se voient

Aujourd'hui : `bar.json → appearance.panelAlpha = 0.0` (pas de dalle) mais
`cardAlpha = 0.99` : chaque module est une pilule presque opaque, plus un flou de fond
(`bar.blur = true`, `blurRadius = 10`) qui laisse une bande floutée sur toute la hauteur.

Attendu :
- **aucun fond par défaut** : ni dalle, ni pilule opaque, ni bande floutée. La barre doit être
  invisible sur le bureau ; on ne voit que les glyphes/textes des modules.
- **l'affordance reste** : au survol/sur actif, une pilule légère apparaît (fond dérivé de la
  palette, pas de hex en dur) — la zone cliquable ne change pas, ≥ 38 px.
- Tous les nouveaux réglages passent par **`bar.json`** (clés nommées et documentées, ex.
  `appearance.blockAlpha: 0.0`, `appearance.hoverAlpha`, `bar.blur: false`) et sont lus par
  `Config.qml` / `BarPalette.qml`. Rien de codé en dur.
- Le `Rectangle id: barBg` **reste déclaré** (il porte la `Region` du `BackgroundEffect` et la
  région d'entrée) : mettre `color: "transparent"` et couper le flou quand `blur=false`, ne pas
  le supprimer (sinon les clics tombent à travers).
- Le contour 1 px (`borderAlpha`) reste à 0 par défaut ; s'il est activé, il suit la palette.

## Tâche 2 — trois boutons de position dans les Réglages

- Nouvelle section « Barre » dans `settings/qml/` (modèle : les sections existantes), avec trois
  boutons **Gauche / Haut / Droite**, l'état courant re-lu **depuis le disque** (`bar.json`).
- Câblage : `→ POST /api/bar` (route déjà présente dans `settings.py`) → écriture
  **chirurgicale** (`barjson.py` : ajouter `--set bar.position=left|top|right` sur le modèle du
  pin/unpin : seul ce champ change, indentation et ordre des clés conservés, écriture atomique,
  relecture de la valeur avant réponse `{"ok":true,"position":...}`).
- **La position doit être réellement honorée par la barre** (sinon le bouton ment) :
  - `left` / `right` : barre verticale plein écran, `anchors.left: true` ou `anchors.right: true`,
    largeur `Config.width` (comportement actuel conservé).
  - `top` : barre horizontale, `anchors.top: true` + `left/right`, hauteur = `Config.width`
    (même épaisseur), largeur = écran, `exclusiveZone` = hauteur, et **les 4 groupes passent en
    `Row`** au lieu de `Column` (mêmes modules, même ordre, même logique d'espacement libre entre
    groupes). Marges : `marginTop` en haut, `marginLeft/marginRight` latérales.
  - `right` : comme `left`, marges miroir (`marginRight`), ordre des groupes inchangé.
  - Un seul `PanelWindow`, jamais deux barres ; pas d'animation sur `exclusiveZone`.
- Valeurs par défaut inchangées (`position: "left"`) pour ne rien casser si le fichier est ancien.
- Documenter la nouvelle clé dans `cc/bar/README.md` (ou NOTES) et dans `install.sh` si un paquet
  est ajouté (aucun paquet attendu).

## Contraintes dures

1. **Ne rien lancer sur le bureau de momo.** Il travaille sur sa machine : interdit de lancer,
   arrêter, relancer ou tester la barre et la fenêtre de réglages (`bar.sh`, `settings.sh`,
   `quickshell -p …`, `hyprctl dispatch …`). Vérification **statique** uniquement, et tu rends une
   checklist que momo exécute lui-même.
2. Palette générée uniquement (`BarPalette` / tokens) — **aucun `#rrggbb`** hors commentaire de
   repli. `qmllint` **Qt6** sur chaque QML modifié :
   `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml <fichier>` (le `qmllint` Qt5 ne valide rien).
3. `bash -n` sur tout script modifié, `python3 -m py_compile` sur `barjson.py` / `settings.py`.
4. Pas de `JSON.stringify` depuis QML : l'écriture passe par `barjson.py --set`.
5. Ne pas toucher `theme-apply*`, `apply-wallpaper.sh`, `cc/server.py` (hors `/api/bar` si
   nécessaire), ni la sidebar.
6. Un commit par tâche, message clair, `git add` explicite (le dépôt peut contenir des modifs de
   momo : lister ce que tu laisses de côté).

## Livrable attendu (rapport)

- fichiers modifiés/créés avec `wc -l`,
- sortie exacte de `qmllint` Qt6 (une ligne par fichier) et des compilations,
- sortie de `barjson.py --set bar.position=top` sur une **copie** de `bar.json`
  (`--file /tmp/bar-copie.json`) : montrer que seul `position` change (`diff`),
- la checklist pour momo : recharger la barre, vérifier les 3 positions, vérifier qu'il n'y a plus
  de fond, et où regarder si un module a disparu en `top`,
- ce qui n'a **pas** été testé en live (par construction) et le premier endroit à inspecter en cas
  de souci.
