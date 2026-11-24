# BRIEF v5a — Contour sub page + section BARRE dans Settings (sans le mode « top »)

Découpage : le mode `position: top` (rangée horizontale) est **v5b**, traité séparément. Ici on livre
deux choses nettes, sans toucher à l'axe de la barre. Ne conçois pas la rangée horizontale dans ce run.

**RÈGLE : momo travaille. Tu ne lances RIEN** (pas de `systemctl`, `quickshell`, `settings.sh`,
`bar.sh`, tests, `hyprctl dispatch`, rofi, `notify-send`, `qs ipc` d'action). Autorisé : lecture,
`qmllint` Qt6 (`/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml`), `bash -n`, `py_compile`,
`python3 -m json.tool`, `grep`, calculs. Preuves dynamiques = checklist pour momo.

## 1. Contour de la sub page (`subpage/shell.qml`)

État : la surface Top contient un `Rectangle` `veil` (transparent, c'est la région d'entrée via
`mask: Region { item: veil }`) et un `Text` サブページ. Aucun cadre.

Ajoute, dans le même `PanelWindow` (layer Top), un `Rectangle` décoratif :
- `anchors.fill: parent` + `anchors.margins: 16` (les `gapsout` de `hypr/conf.d/rules.conf`),
- `color: "transparent"`, `border.width: 1`, `radius: 13`,
- `border.color: Qt.rgba(cStroke.r, cStroke.g, cStroke.b, 0.55)` où `cStroke` est **déjà défini**
  dans le fichier (`Qt.lighter(shell.cAccent, 1.9)`) — aucun hex,
- `visible: shell.specialOpen` (comme la teinte et l'étiquette),
- **ne participe pas au `mask`** : la région d'entrée reste `veil` seule, le cadre ne capte aucun clic,
- aucun blur, aucun remplissage, rien d'autre n'est ajouté (pas de coins, pas de voile).

Réglage facultatif dans `settings.json` : section `subpage: {"frame": true, "frame_alpha": 0.55,
"frame_radius": 13}` lue comme les autres sections du panneau Settings ; défaut = cadre actif. Si tu
l'ajoutes, elle doit être prise en compte **sans redémarrer** la sub page (lecture au changement, comme
le fait déjà `settings.py` pour les autres clés).

## 2. `cc/bar/barjson.py` : écriture d'une clé quelconque

Ajoute `--set <chemin>=<valeur>` (ex. `--set bar.width=44`, `--set appearance.cardAlpha=0.7`,
`--set bar.blur=false`, `--set bar.persistentWorkspaces=10`, `--set runningApps.maxVisible=4`) :
- écriture atomique (tmp même dossier + `os.replace`), **ordre et indentation du fichier conservés**,
  seule la clé visée change ; une section absente (`runningApps`) est créée **au bon endroit** ;
- bornes par clé (table dans le script) : refuse hors bornes avec `{"ok": false, "error": "…"}` ;
- valeurs typées : nombre / booléen / chaîne (`left|right` pour `bar.position` en v5a) ;
- sortie JSON sur une ligne, code 0 sauf plantage ; ne casse jamais le fichier (JSON invalide → refus).

## 3. `settings/settings.py` + `settings/main.qml` : section « BARRE »

Section **en premier** dans la colonne de contenu, avant LANGUE, avec les composants existants
(`Section`, `SliderRow`, `Toggle`, `FieldRow`).

Contrôles (tous → `cc/bar/bar.json`, source unique) :
| Contrôle | Clé | Type | Bornes |
|---|---|---|---|
| Position (côté) | `bar.position` | 2 segments | `left` · `right` (top = v5b, ne pas l'exposer) |
| Épaisseur | `bar.width` | slider | 32–64 |
| Transparence des pilules | `appearance.cardAlpha` | slider | 0.50–1.00 |
| Flou | `bar.blur` | toggle | on / off (no blur) |
| Workspaces persistants | `bar.persistentWorkspaces` | slider | 0–12 |
| Apps en cours visibles | `runningApps.maxVisible` | slider | 1–6 |

- `GET /api/bar` → valeurs **relues depuis `bar.json`** (jamais une copie mémoire du panneau) ;
- `POST /api/bar` `{key, value}` → subprocess `python3 <repo>/cc/bar/barjson.py --set key=value`,
  remonte l'erreur du writer telle quelle dans la réponse ;
- après écriture, la section relit (`GET /api/bar`) et affiche la valeur réelle ;
- si `bar.json` est absent/illisible : section en lecture seule avec message, pas de crash ;
- aucun doublon de ces valeurs dans `settings.json`.

## 4. Ne pas casser / ne pas toucher

- `panelAlpha` reste 0 (pas de dalle), apps épinglées inchangées (krita incluse), pas de grab clavier.
- Ne pas toucher `cc/main.qml`, `cc/sidebar/`, `cc/server.py`, `theme-apply.py`, `waybar/`,
  `~/.config/rofi/`, ni `cc/bar/modules/*` (sauf si une clé lue par un module doit être exposée :
  `runningApps.maxVisible` devra être lu depuis `Config` → alors seulement ce fichier).
- `qmllint` après chaque édition QML, `//` uniquement en QML, `bash -n`/`py_compile` sur les scripts.
- Staging **fichier par fichier**.

## 5. Rapport (court, pas de dissertation)

1. Fichiers + `git status --short` + staging.
2. Sorties `qmllint` / `bash -n` / `py_compile` / `json.tool`.
3. `--set` testé sur une **copie** de `bar.json` : la clé change, **diff du reste = vide** (colle le diff).
4. Coordonnées calculées du cadre de la sub page pour 1920×1080.
5. Checklist momo : Super+S → cadre visible, clics normaux ; Super+I → section BARRE en haut, chaque
   contrôle écrit (`git diff -- cc/bar/bar.json`) et la barre suit à chaud ; « no blur » coupe bien
   le flou.
