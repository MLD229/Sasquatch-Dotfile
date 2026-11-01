# RAPPORT rin — transparence réelle, filets blancs, Studio à jour

Brief : `docs/BRIEF-rin-transparence.md`. Repo `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`).
Captures : `docs/rin-transparence-accueil.png`, `docs/rin-transparence-studio-apercu.png`,
`docs/rin-transparence-studio.png` (preuve d'ajout sans redémarrage).

## 1. Filets blancs — supprimés

| | |
|---|---|
| **Symptôme** | un trait clair de 1 px court en haut de chaque carte et chaque carte garde un contour pâle au repos (visible sur `docs/rin-v1c2-studio.png`) |
| **Cause** | `WidgetBase.qml` dessinait trois traits superposés : le filet `Theme.light` (texte à 12 %), `border.width: 1` + `Theme.border` sur la carte, et le même `border` sur `GlassCard.qml`. `ToolsPage` et les lignes du catalogue Studio avaient aussi des bordures `Theme.a(Theme.text, 0.05–0.08)` (blanc à 5–8 %) |
| **Correctif** | filet `Theme.light` supprimé, token `light` retiré de `Theme.qml` ; plus aucune bordure de carte (WidgetBase, GlassCard) ; contour **uniquement** en édition (1 px accent) ou au survol (1 px accent 0.55, `WidgetBase.hovered`) ; boutons de `ToolsPage` en contour-au-survol, champ de recherche en contour-au-focus ; bordure des lignes du catalogue Studio retirée |
| **Preuve** | `qmllint` 0 erreur sur 53 fichiers ; `docs/rin-transparence-accueil.png` : aucune arête claire sur les 7 cartes, glyphes et jauges nets |

## 2. Transparence SANS blur

| | |
|---|---|
| **Symptôme** | les cartes formaient une plaque grise autour des textes et le halo flouté créait une arête trouble |
| **Cause** | `MultiEffect` (rebord flouté `Theme.rim` + `blurEnabled`) dans `WidgetBase.qml` **et** `GlassCard.qml`, plus un remplissage `alpha` de 0.24 / 0.15 |
| **Correctif** | `MultiEffect` et halo supprimés des deux fichiers (plus de `blurEnabled`, plus de `Theme.rim/rimBlur/rimMax`, `blurFor()` retiré) ; remplissage `alphaCard` 0.24 → **0.08**, `alphaHero` 0.15 → **0.05**, bornes `style.alpha` du registre 0.10–0.90 → **0.03–0.35** (`registry.json`, lues par le Studio **et** par `widgets_json.py`) ; les 8 instances de `widgets.json` migrées par `POST /api/widgets` (op `style`) vers 0.08 / 0.05 ; **aucun** `BackgroundEffect`/`blurRegion` dans `cc/` (il n'en restait aucun hors `bar/` et `sidebar/`, non touchés) ; `style.blur` **conservé dans le schéma mais inerte**, documenté dans `Theme.qml`, `WidgetRegistry.qml`, `widgets_json.py` et affiché grisé « sans effet » dans le Studio (curseur verrouillé) ; contenus inchangés à 100 % d'opacité |
| **Preuve** | `docs/rin-transparence-accueil.png` : aucune zone grise uniforme, texte/jauges pleinement opaques ; panneau STYLE du Studio : `Alpha 0.08`, `Blur  sans effet` (grisé) ; `grep MultiEffect` = 0 dans `WidgetBase`/`GlassCard` |

## 3. Studio — les widgets posés sont visibles et à jour

| | |
|---|---|
| **Symptôme** | dans l'espace d'ajout, les widgets posés sur l'aperçu du fond ne se voyaient pas / ne se mettaient pas à jour |
| **Cause** | trois défauts cumulés : (a) le widget de l'aperçu démarrait en édition avec des liaisons `width/height` **directes** qui se réappliquaient pendant le drag — la poignée de resize était donc annulée ; (b) aucun retour explicite : un composant non livré ou en échec laissait un trou invisible et rien ne disait combien d'instances étaient réellement dessinées ; (c) `applyText()` ignorait le fichier dès que la révision était la même, donc une modification venue d'un **autre** hôte n'arrivait jamais dans l'aperçu |
| **Correctif** | géométrie du wrapper pilotée uniquement par les `Binding` (`when: !editing`) + amorçage x/y/**w/h** en édition ; **vignette d'attente explicite** par instance (`WidgetCanvas`, `objectName: widget-pending`, texte « composant non livré / échec de chargement · type ») affichée tant que le `Loader` n'est pas `Ready` ; compteur de rendu publié par les `Loader` eux-mêmes (`WidgetCanvas.readyCount` / `pendingCount` → `StudioPage.previewReady/previewPending`) affiché en pied de page « rendu N/M » ; relecture du fichier dès que le nombre d'instances diffère ; rendu de l'aperçu par le **même** composant que l'hôte réel (registre → `Loader`, déjà en place) avec `variant`/`style`/`options` de l'instance ; masque `MultiEffect` du papier peint remplacé par un simple `clip` (aucun effet dans l'aperçu) ; `cc-preview.qml` ne sélectionne plus un id en dur |
| **Preuve** | `cc/widgets/tests/studio-probe.qml` (nouveau harnais, jamais le CC plein écran) : `AVANT | instances 1 [clock-1] | rendu 1/1 | revision 102` → `APRES | instances 2 [clock-1,calendar-3] | rendu 2/2 | en attente 0 | POST 1` → `docs/rin-transparence-studio.png` montre le calendrier posé dans l'aperçu, le panneau STYLE rempli et le pied « révision relue 103 · POST 1 · rendu 2/2 ». Aucun redémarrage. Le fichier ressort intact (sonde : `reste 1`) |

## Vérification finale (une seule passe)

```
qmllint (Qt6, 53 fichiers QML : module, pages, harnais, main.qml) .... 0 échec
curl /api/widgets ....... 8 instances, alpha 0.08 (0.05 hero), revision 104
cc-preview (4 rendus) .... Configuration Loaded, 4 PNG, 0 WARN
studio-probe ............ ajout visible sans restart, rendu 2/2, 0 en attente
```

Note : `cc/qml/Palette.qml` échoue à `qmllint` **avant** ce passage — ce n'est pas un fichier QML mais
le fragment de palette injecté dans `main.qml` par `theme-apply.py` (marqueurs `SASQUATCH-PALETTE-*`).

## Fichiers touchés

```
cc/widgets/Sasquatch/Widgets/Theme.qml          alpha 0.08/0.05, tokens flou retirés
cc/widgets/Sasquatch/Widgets/WidgetBase.qml     filet + halo + bordure retirés, survol accent
cc/widgets/Sasquatch/Widgets/GlassCard.qml      halo + bordure retirés
cc/widgets/Sasquatch/Widgets/WidgetCanvas.qml   vignette d'attente, compteurs de rendu, resize
cc/widgets/Sasquatch/Widgets/WidgetRegistry.qml style par défaut 0.08/0.05, bornes alpha
cc/widgets/Sasquatch/Widgets/registry.json      bornes alpha [0.03, 0.35] (15 entrées)
cc/widgets_json.py                              défaut alpha 0.08, bornes de repli
cc/pages/StudioPage.qml                         papier peint en clip, Blur verrouillé, compteur, relecture
cc/pages/ToolsPage.qml                          contour au survol / au focus seulement
cc/widgets/tests/cc-preview.qml                 sélection sans id en dur
cc/widgets/tests/studio-probe.qml               nouveau : preuve « ajout visible sans restart »
cc/widgets.json                                 8 instances migrées (alpha) via POST /api/widgets
docs/rin-transparence-*.png, docs/RAPPORT-rin-transparence.md
```

Interdits tenus : `cc/main.qml` jamais lancé en plein écran (harnais 1200×760 layer Top uniquement),
keybinds et fichiers de momo hors périmètre intacts, aucun `pkill`, aucun commentaire dans un `.json`.
