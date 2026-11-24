# BRIEF v5 — Contour de la sub page + panneau « BARRE » dans Settings (2026-10-31, nuit)

**RÈGLE : momo travaille sur sa machine. Tu ne lances RIEN** (pas de `systemctl`, `quickshell`,
`bar.sh`, `hyprctl dispatch`, rofi, `notify-send`, `qs ipc` d'action, ni les suites de tests).
Autorisé : lecture, `qmllint` Qt6, `bash -n`, `py_compile`, `python3 -m json.tool`, `grep`, calculs.
Preuves dynamiques = checklist pour momo.

Contexte : barre verticale `cc/bar` en service (40 px, îlots, `panelAlpha` 0), waybar retirée
(unité liée mais `disabled`), gardes dans `scripts/theme-apply.sh` et `scripts/apply-lang.sh`.
Lis `cc/bar/README.md`, `cc/bar/PROGRESS.md` (pièges 1-24) et `subpage/README.md` avant de coder.

---

## 1. Contour sur la sub page (scratchpad)

Aujourd'hui la sub page n'a **que** : une teinte chaude de fond (`subpage-bg`, layer Background) et
une étiquette サブページ dans la gouttière du haut. Aucun cadre n'est dessiné (`subpage/shell.qml`,
surface Top : un `Rectangle` `veil` transparent qui définit la région d'entrée + le `Text`).

Ajouter un **contour** lisible, sans rien réintroduire de ce qui avait été refusé (pas de voile
assombrissant, pas de « carrés bleus » dans les coins, pas de blur) :

- 1 px (ou 1,5) de trait, couleur **dérivée** de l'accent (`Qt.lighter(cAccent, …)` ou token
  `Palette.qml`), alpha ≈ 0.5–0.6, rayon ≈ 12–14, **inset = les gaps de la page**
  (`rules.conf` : `gapsout:16`, `gapsin:6` → cadre à 16 px des bords de l'écran).
- **Aucun remplissage** (`color: "transparent"` + `border.width`), donc rien ne recouvre les
  fenêtres et rien ne floute.
- Visible **seulement** quand la page est ouverte (`shell.specialOpen`) — même logique que la
  teinte et l'étiquette.
- **Ne doit pas capter les clics** : la région d'entrée reste `veil` (`mask: Region { item: veil }`).
  Le cadre est purement décoratif ; à la limite, la zone d'entrée peut rester identique au pixel près.
- L'étiquette et le cadre doivent s'accorder (même famille de couleur, même marge).
- Un seul interrupteur pour le tout : `bar.json` ne gère pas la sub page — si un réglage est utile,
  mets-le dans `settings.json` (`subpage: { frame: true, frame_alpha: 0.55, frame_radius: 13 }`) et
  relis-le comme les autres sections ; défaut = cadre actif.

Vérification attendue : schéma (positions calculées du cadre pour 1920×1080) + procédure pour que
momo ouvre la sub page (Super+S) et regarde.

## 2. Un espace « BARRE » dans Sasquatch Settings

Le panneau `settings/` (Python 8770 + `main.qml`, sections LANGUE / VEILLE / APPARENCE / HORLOGE /
RACCOURCIS) doit gagner une section **BARRE** en haut de la liste (momo l'a demandée « en haut »),
avec des composants qui existent déjà : `Section.qml`, `SliderRow.qml`, `Toggle.qml`, `FieldRow.qml`.

Réglages à exposer (tous écrits dans **`cc/bar/bar.json`**, source unique — rien de dupliqué dans
`settings.json`) :

| Réglage | Clé bar.json | Contrôle | Valeurs |
|---|---|---|---|
| Position | `bar.position` | 3 boutons radio/segments | `left` · `right` · `top` |
| Épaisseur (largeur si côté, hauteur si haut) | `bar.width` | slider | 32–64 px |
| Transparence des pilules | `appearance.cardAlpha` | slider | 0.50–1.00 |
| Flou | `bar.blur` | toggle | on / **off (no blur)** |
| Workspaces persistants | `bar.persistentWorkspaces` | slider | 0–12 (0 = seulement les existants) |
| Apps en cours visibles | `runningApps.maxVisible` (nouvelle clé) | slider | 1–6 |

Exigences :
- **Écriture chirurgicale** : étendre `cc/bar/barjson.py` avec `--set <chemin>=<valeur>`
  (ex. `--set bar.position=top`, `--set appearance.cardAlpha=0.7`, `--set runningApps.maxVisible=4`),
  écriture atomique, clés inconnues créées au bon endroit sans réécrire l'ordre, indentation
  conservée, valeur refusée si hors bornes (réponse JSON `{"ok": false, "error": …}`).
- `settings.py` : routes `GET /api/bar` (valeurs courantes) et `POST /api/bar` (une clé → appelle le
  writer), plus l'enregistrement de la section dans la réponse `/api/state` si c'est le mécanisme
  existant. Aucune modification de `cc/bar/bar.json` par un `json.dump` global.
- **Rechargement** : la barre écoute déjà `bar.json` (FileView) → le changement s'applique en < 2 s,
  sans redémarrer la barre. La section doit afficher les valeurs **réelles** relues après écriture
  (pas une copie en mémoire du panneau).
- Valeurs par défaut cohérentes : `position: left`, `width: 40`, `cardAlpha: 0.86`, `blur: true`,
  `persistentWorkspaces: 10`, `maxVisible: 3`.
- Le panneau doit rester utilisable si la barre n'est pas lancée (lecture = fichier, pas d'IPC).

## 3. Position « haut » = vraie mise en page horizontale

`bar.position` existe déjà dans le schéma mais n'est pas implémenté. Il faut :
- **côté** (`left`/`right`) : comportement actuel ; `right` = miroir (ancrage droite, `exclusiveZone`
  à droite, popups/infobulles à gauche).
- **haut** (`top`) : les mêmes îlots, en **rangée** : ancrage haut, hauteur = `bar.width`, largeur
  = écran moins les marges ; `exclusiveZone` = hauteur + marge haute ; répartition
  gauche (recherche, workspaces) · centre (débit, horloge, volume) · droite (apps, « + », en cours,
  toggles, engrenage) — **une seule règle d'espacement**, les îlots gardent le même style ;
  popups et infobulles s'ouvrent **sous** la barre ; la molette verticale reste sur les mêmes modules.
- Aucune duplication de logique : un seul `shell.qml` qui choisit l'axe (Row vs Column) et l'ancrage,
  les modules ne changent pas de taille (bloc = `Config.block` dans les deux sens).
- Changement de position **à chaud** (via `bar.json`), sans redémarrer le service : `WlrLayershell`
  exige de recréer la surface → utiliser un `Loader`/`Repeater` sur les ancrages, ou documenter
  honnêtement que la position demande un restart (`bar.sh`) et le dire dans le README.

## 4. Contraintes

- Aucune couleur en dur hors `BarPalette.qml` ; pas de grab clavier ; popups `WlrKeyboardFocus.OnDemand`.
- Ne pas réintroduire de fond de barre (`panelAlpha` reste 0), ne pas toucher aux apps épinglées de
  `cc/bar/bar.json` (krita incluse), ni `cc/main.qml`, `cc/sidebar/`, `cc/server.py`,
  `theme-apply.py`, `waybar/`, `~/.config/rofi/`.
- `qmllint` après chaque édition QML, `//` uniquement en QML, `bash -n`/`py_compile` sur les scripts.
- Staging **fichier par fichier** (le dépôt porte des modifications de momo).
- Si un point du brief s'avère impossible (ex. changement de `WlrLayershell` à chaud), dis-le
  clairement dans le rapport au lieu de livrer un demi-mécanisme.

## 5. Rapport attendu

1. Fichiers + `git status --short`, staging explicite.
2. Sorties `qmllint` (Qt6), `bash -n`, `py_compile`, `json.tool` sur `bar.json`.
3. Avant/après d'un `--set` sur **copie** de `bar.json` (une clé ajoutée, reste du fichier identique).
4. Schéma du cadre de la sub page (coordonnées calculées) et du mode `top` (positions des îlots).
5. **Checklist momo** : (a) sub page via Super+S → contour visible, fenêtres intactes, clics
   normaux ; (b) Super+I → section BARRE en haut, chaque contrôle écrit bien dans `bar.json`
   (`git diff -- cc/bar/bar.json`) et la barre suit à chaud ; (c) passage `top` puis retour `left`.
6. Ce qui reste non prouvable sans toucher au bureau.
