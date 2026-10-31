# PROGRESS — barre verticale (rin)

Journal de bord. La session peut être tuée : reprendre à la dernière étape non cochée.

## 0. Relevé initial (fait)
- Dépôt /home/momo/Downloads/Sasquatch-Dotfile, branche main, 10 fichiers modifiés + untracked qui ne sont PAS de moi (ne pas stager).
- cc/bar/ n'existait pas (seulement reference/barre-ref.png).
- Backend CC 8765 actif : /api/palette, /api/stats, /api/system/volume {volume,muted},
  /api/system/brightness {brightness}, POST volume body {"v":N} ou {"mute":bool}, POST brightness {"v":N}.
- Hyprland : 1 écran eDP-1 1920x1080, reserved=[0,42,0,0] (waybar 42 px), blur enabled=1.

## Étapes
- [x] 1. bar.json + qml/Config.qml (validation + hot reload + défauts dans le code)
- [x] 2. appindex.py (--json / --launch) testé : 49 apps, 72 classes, 0.17 s
- [x] 3. qml/BarPalette.qml (2 s, lift d'accent) + qml/Backend.qml (timer unique 2 s)
        NOTE : le singleton s'appelle BarPalette, pas Palette — le nom « Palette »
        est déjà pris par un type QtQuick et le QML résolvait le mauvais objet.
- [x] 4. composants qml/ : Pill, BarIcon, IconButton, AppIcon, Badge, Section, Tip, Ui, Hypr
- [x] 5. modules/ : Search, Workspaces, NetRate, Clock, VolumeSlider, AppDock, RunningApps, QuickToggles, Settings
- [x] 6. popups/ : Calendar, Volume, Network, Notifications, Windows
- [x] 7. shell.qml : ShellRoot, bar PanelWindow (exclusiveZone), infobulle, 5 popups, IpcHandler
        Premier lancement OK. Corrigé : Process sans `import Quickshell.Io`,
        Process.exitCode inexistant (→ onExited(code,status)), zones qui se
        chevauchaient (mid ancré entre top et bottom).
- [x] 8. bar.sh (détection par /proc, pas de pkill -f auto-tueur) + bar.service
- [x] 9. vérifs §12 : qmllint 28/28, bash -n, layer xywh, croisement valeurs, toggle x2,
        hot reload (width 56→72→56, JSON cassé → config conservée, module retiré/remis)
- [x] 10. install.sh + keybinds + README + coupure waybar + service actif

## État final
- Barre : `sasquatch-bar.service` actif (quickshell -p ~/.config/cc/bar/shell.qml),
  démarrage auto par default.target.wants (graphical-session.target est INACTIF ici).
- Waybar : `disable --now` fait ; unité restée `linked` → `systemctl --user enable --now waybar`
  suffit pour revenir en arrière.
- Captures livrées : cc/bar/tests/artifacts/{barre-finale.png, ecran-final.png,
  popup-calendrier.png, popup-volume.png}.

## Pièges rencontrés (à ne pas repayer)
1. Singleton nommé `Palette` → QtQuick en a déjà un ; le QML résolvait le mauvais objet
   (`Property 'a' of object QtQuick/Palette is not a function`). Renommé `BarPalette`.
2. `Process` exige `import Quickshell.Io` — un popup qui en utilise un ne démarre pas sinon.
3. `Process.exitCode` n'existe pas en 0.3.2 → `onExited: function (code, status)`.
4. `function f(): void` dans un IpcHandler fait PLANTER qmllint (exit 255, sortie vide).
   Retirer l'annotation `: void` (les fonctions restent enregistrées) ; `: string` OK.
5. Les popups (layer surfaces) sont positionnés DANS la zone réservée : marge 10 px,
   pas 72 (sinon la popup part à 134 px).
6. Les trois colonnes (haut/centre/bas) se chevauchent si la somme dépasse la hauteur :
   le centre est ancré entre `topZone.bottom` et `botZone.top`.
7. `systemctl --user disable` supprime aussi le lien d'unité dans ~/.config/systemd/user
   → re-lier après (waybar et sasquatch-bar).

## Mesures relevées
- `hyprctl layers` : namespace sasquatch-bar, x=6 y=50 w=56 h=1022 (waybar active, top réservé 42)
- `monitors[0].reserved` = [62, 42, 0, 0] → 62 = width 56 + marginLeft 6
- Toggle OFF : plus de process, plus de layer, reserved = [0, 42, 0, 0]
- Toggle ON  : layer de retour, reserved = [62, 42, 0, 0]
- Hot reload width=72 : surface w=72, reserved [78, 42, 0, 0]
- JSON cassé : surface vivante, width 72 conservée, configError = "JSON invalide (JSON.parse: Parse error)"

---

# v2 — polish (2026-10-31, session rin)

Brief : `docs/BRIEF-rin-barre-v2-polish.md`. Architecture inchangée (PanelWindow
gauche, service `sasquatch-bar`, `bar.json`, palette `/api/palette`, `bar.sh` →
systemctl).

## Étape 1 — clic app = aller là-bas (FAIT)
Cause racine trouvée (deux, en fait) :
1. `HyprlandToplevel.address` expose l'adresse **sans** préfixe `0x` ; Hyprland
   n'accepte que `focuswindow address:0x…` → `WARN No such window found`
   (vérifié : même adresse, sans 0x = échec, avec 0x = ok).
2. `lastIpcObject.focusHistoryID` ne se rafraîchit pas au changement de focus
   → « la plus récemment active » était fausse.

Correction : `Hypr.request()` lit `hyprctl clients -j` AU MOMENT DU CLIC
(1 exécution par clic, aucun timer), trie par `focusHistoryID` croissant,
dispatche `workspace <ws>` puis `focuswindow address:0x…`, et replanifie UNE
résolution si l'adresse a disparu (vérification 250 ms après).
IPC de test : `focusApp <classe>`, `clickApp <id bar.json>`, `cycleApp`,
`windows`, `clicks`, `rects`.

Preuve : kitty ws1 + kitty ws2, clic simulé via `qs ipc call bar focusApp kitty` :
`activeworkspace` 7 → 1 puis 8 → 2, `activewindow` = kitty à chaque fois,
`No such window found` = 0 depuis le redémarrage.

## Étape 2 — largeur 46 + blocs recalculés (FAIT)
`bar.json` : `width` 56→46, `spacing` 8, `blockInset` 4, `radius` 16,
`blurRadius` 10. `Config.block = width - 2*inset` = 38, `Config.hit =
max(38, block)`. Aucune taille de bloc en dur dans les modules : ils lisent
`Config.block` / `Config.iconSize` / `Config.appIconSize` / `Config.clockSize`
/ `Config.netSize`. Vérifié à 46 (38) — le code suit 44→56 sans retouche.

Corrigé au passage : `Text` en `renderType: Text.NativeRendering` dans la
barre (l'AA sous-pixel produisait des franges colorées sur surface translucide,
mesuré : 94 pixels colorés sur le « 12 » de l'horloge, 0 après).

## Étape 3 — alpha (FAIT)
`appearance` : panelAlpha 0.24, cardAlpha 0.20, hoverAlpha 0.35,
activeAlpha 0.34, borderAlpha 0.12, borderHoverAlpha 0.30 — toutes lues par
`BarPalette` (aucun alpha en dur). Bordure de pilule seulement au survol
(`Pill.border.width` = 0 au repos).
Mesures pixel (2 points, méthode dans le rapport) : panneau 0.237 (config 0.24),
carte 0.200 (config 0.20), survol 0.345 (config 0.35).

## Étape 4 — centrage (FAIT)
Refonte des zones : UN `ColumnLayout` (5 enfants : groupe haut, ressort,
groupe centre, ressort, groupe bas). Les `ColumnLayout` imbriqués portent
`Layout.alignment: Qt.AlignHCenter` + `Layout.preferredWidth: Config.block`
(les ancres de Layout sur les délégués d'un `Repeater` sont ignorées → blocs
collés à gauche, cx=19 au lieu de 23 : corrigé).
`rects` : 25 blocs, x=4 unique, w=38 unique, cx=23 unique (= 46/2).
Bug trouvé par la mesure : chevauchement de 11 px entre le dernier point de
workspace et le débit (hauteurs chaînées sur `implicitHeight`) → plus aucun
chevauchement, dernier bloc à y=1054 (barre 1064).
Budget vertical : points de workspace 20→18, horloge 76→72, volume 116→108,
`maxVisible` apps en cours 4→3 (au-delà : pastille « +N »).

## Étape 5 — boutons (FAIT)
`IconButton` / `AppIcon` : 38 × 38 (`Config.hit`), zone cliquable = rectangle
dessiné. Nouveau `qml/HitButton.qml` (38 × 38) pour les commandes des popups
(fermer, mois ±1, corbeille) ; en-têtes de popups passés à 38 px.
Chaque module enregistre ses actions dans `Ui` : `qs ipc call bar action <nom>`
exécute EXACTEMENT le code du bouton (aucun simulateur de souris sur ce poste).
`Ui.dumpRects()` → `bar rects` : 25 cibles, largeur 38 unique, centre 23 unique,
`hitMatchesVisual` vrai partout.
Cible introuvable = notification : vérifié avec `clickApp fantome` →
`makoctl history` contient « app inconnue dans bar.json : fantome ».

## Étape 6 — engrenage → Sasquatch Settings (FAIT)
`modules/Settings.qml` : `hyprctl dispatch exec ~/.config/settings/settings.sh`,
infobulle « Réglages (Super+I) », test d'existence au démarrage (glyphe chaud +
infobulle si absent), notification si le lancement échoue. Le Control Center
n'est plus derrière ce bouton.
Preuve : `qs ipc call bar action settings` → `hyprctl clients` = 1 fenêtre
`Sasquatch Settings`, `curl 127.0.0.1:8770/api/health` = {"ok": true},
capture `tests/artifacts/v2/reglages-ouverts.png`. Le panneau étant un toggle,
il a été refermé après le test.

## Étape 7 — suites et mesures
- `bash tests/verify-v2.sh` : 21 OK, 0 FAIL (sections §1, §2, §3, §5, §6).
- `bash tests/run-all.sh` : tout vert, 29 fichiers QML, reserved [52,0,0,0].
- `qmllint` 29/29 sans sortie · `bash -n` bar.sh + 2 suites · `py_compile`.
- Aucune couleur en dur hors `BarPalette` (valeurs de secours commentées).
- Aucun grab clavier (`WlrKeyboardFocus.None`).

## Mesures v2 (à réutiliser)
- surface : x=6 y=8 w=46 h=1064 ; `reserved` = [52,0,0,0] (= 46 + marginLeft 6)
- cibles : 25 blocs, x=4, w=38, centre x+w/2 = 23 (= 46/2) pour TOUTES
- alphas mesurés au pixel : panneau 0.237 (cfg 0.24) · carte 0.200 (cfg 0.20) ·
  survol 0.345 (cfg 0.35) · bordure de pilule : alpha 0 au repos
- contenu : 988 px de haut dans 1064 (dernier bloc à y=1054), 0 chevauchement
- glyphes : icônes 16 px, apps 20 px, horloge 15 px, débit 9 px
- franges sous-pixel de l'horloge : 94 px colorés → 0 après `NativeRendering`

## Pièges v2 (à ne pas repayer)
8. `HyprlandToplevel.address` est SANS `0x` → `focuswindow` échoue
   (« No such window found »). Toujours `Hypr.addr0x()`.
9. `lastIpcObject.focusHistoryID` ne suit pas les changements de focus →
   lire `hyprctl clients -j` au moment du clic.
10. Ancres sur les enfants d'une `Column`/`Row` : QML les ignore ou les place
    n'importe où (le débit s'affichait sur une seule ligne). Toujours un `Item`
    pleine largeur + `anchors.centerIn`.
11. `Layout.alignment` sur les délégués d'un `Repeater` dans un `ColumnLayout`
    n'est pas appliqué (blocs collés à gauche, cx=19) → porter l'alignement sur
    le `ColumnLayout` imbriqué.
12. Chaîner `height: zoneCol.implicitHeight` entre zones donne 11 px de
    recouvrement → un seul `ColumnLayout` racine avec deux ressorts.
13. `return` dans une fonction `IpcHandler` non annotée → ERROR
    « should be coerced to void » dans le journal.

---

# v3 — molette, épinglage, état actif, centrage (2026-10-31, soir)

Brief : `docs/BRIEF-rin-barre-v3.md`. **Session sans aucune action système**
(momo travaillait) : lecture, `qmllint`, `bash -n`, `py_compile`, tests de
`barjson.py` sur une COPIE, preuves dynamiques différées (checklist §8).

## Étape 1 — loupe = lanceur du dotfile (FAIT)
`modules/Search.qml` : `~/.config/rofi/scripts/launcher.sh` existe (vérifié
`test -x`, mode 755) → `hyprctl dispatch exec ~/.config/rofi/scripts/launcher.sh`
(même style que Settings v2), repli `rofi -show drun -theme
~/.config/rofi/themes/sasquatch.rasi` (thème présent, 4811 o), état visible
« lanceur introuvable » si les deux manquent (glyphe chaud + point + infobulle).

## Étape 2 — zones de molette plein bloc (FAIT)
- `qml/WheelZone.qml` (nouveau) : `acceptedButtons: Qt.NoButton`,
  `hoverEnabled: false`, `z` par défaut → posée SOUS le contenu, ne prend que
  la molette ; elle publie `name`, `lastStep`, `lastY`.
- `Workspaces` : un seul `MouseArea` pour tout le bloc (clic routé par
  l'ordonnée, molette = ws précédent/suivant) — le `onWheel` par point a
  disparu (cause du « rien entre deux points »).
- `AppDock` : WheelZone « pinned » + molette des icônes renvoyée à
  `mod.cycleEntry` (même code) ; `Hypr.cycleApp` repart de la classe RÉELLE.
- `RunningApps` : fenêtre glissante (`offset`, 3 visibles) + piste/curseur à
  droite ; molette = défilement (plus de « +N »).
- `VolumeSlider` : inchangé (±5 %), enregistré comme zone (`bar wheels`).
- IPC : `bar wheels` → `[{name, x, y, w, h}]`.

## Étape 3 — épinglage depuis la barre (FAIT)
- `barjson.py` (nouveau) : `--pin/--unpin <id>`, édition TEXTUELLE du seul
  tableau `apps` (offset trouvés par scan d'accolades), indentation détectée,
  `os.replace` atomique, garde-fou « tout le reste identique » sinon aucune
  écriture, refus lecture seule / JSON invalide / app inconnue.
- `qml/PinWriter.qml` (nouveau) : appelle le script, journalise (Hypr.note +
  notify-send), expose `lastError` / `revision`.
- `popups/AddAppPopup.qml` (nouveau) : « + » → recherche sur `AppIndex.apps`
  (tri par nom), icône par ligne, point d'accent si déjà épinglée, clic →
  `PinWriter.pin` + fermeture.
- `popups/AppMenuPopup.qml` (nouveau) : clic droit → « Détacher » (épinglée) /
  « Épingler » (en cours) + « Fenêtres » ; clic milieu = fenêtres directement.
- IPC : `pinApp`, `unpinApp`, `addApp`.

## Étape 4 — état actif visible (FAIT)
- `Hypr.appKeys/appWindows/countOfApp/isOpenApp/pinnedState` : `norm` des deux
  côtés + id `.desktop` (+ `AppIndex.classes` pour classe → id).
- `Pill` : contour d'ACCENT à l'état actif ; `bar.json` `activeAlpha`
  0.34 → 0.46 (défaut `Config` aligné) ; `AppIcon` : barre d'accent 3×22 +
  halo `accentSoft` + badge.
- `bar state` → `pinnedOpen: {id: bool}`.
- Vérifié sur données RÉELLES (lecture seule `hyprctl clients -j`) : discord →
  `discord`, fichiers → `org.kde.dolphin` (clés `dolphin`/`orgkdedolphin`),
  terminal → `kitty`. `spotify` fermée ce soir-là → `false` attendu.

## Étape 5 — centrage des glyphes (FAIT)
Cause mesurée : en monospace, l'avance d'un glyphe = 0,6 em (9,59 px à 16 px)
alors que l'encre peut faire 19 px (wifi U+F1EB, son U+F028) → `anchors.centerIn`
centrait l'AVANCE, l'encre partait de 4,7 px à droite. `BarIcon` devient un
conteneur qui centre l'ENCRE (table `glyphe → [dx, dy]` mesurée avec PIL sur
`JetBrainsMonoNerdFont-Regular.ttf`, `getbbox(anchor="ls")`), mise à l'échelle
avec `size`. Chiffres/lettres : écart ≤ 0,25 px → pas de compensation.
Débit réseau : −1 px explicite (la virgule descend).

## Contrôles statiques rejoués
- `qmllint` : **33 fichiers QML, 0 erreur**. ATTENTION : `/usr/bin/qmllint` est
  celui de **qt5-declarative 5.15** (« QML syntax verifier »), il ne signale
  presque rien. Le vrai linter Qt6 est `/usr/lib/qt6/bin/qmllint` (6.12.0) :
  passé sur les 33 fichiers avec `-I /usr/lib/qt6/qml` → 0 erreur, seulement
  des avertissements de style déjà présents en v2 (`unqualified access`,
  `PanelWindow is not creatable`, singletons hors qmldir).
- `bash -n` bar.sh + tests ; `py_compile` appindex.py + barjson.py.
- `barjson.py` sur COPIE : ajout, doublon (réactivation, `changed:false`),
  détachement (`enabled:false`), lecture seule, JSON cassé, app inconnue ;
  identité octet-pour-octet hors section `apps` vérifiée.

## À faire par momo (dynamique)
Voir la checklist du rapport (§8) : redémarrer le service, loupe, molette sur
chaque module, « + », détachement, `bar state | jq .pinnedOpen`.

## Pièges v3 (à ne pas repayer)
14. `/usr/bin/qmllint` = Qt5 (syntaxe seule) : utiliser
    `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml`.
15. Un glyphe Nerd Font large déborde son avance : centrer l'avance ≠ centrer
    l'encre (jusqu'à 4,75 px d'écart à 16 px).
16. `id: wheel` dans un `MouseArea` masque le signal `wheel` → nommer
    `wheelZone` (avertissement `id-shadows-member`).
17. Un `Process` Quickshell avec `command: []` n'aime pas être lancé : mettre
    une commande inerte (`/usr/bin/true`) et la remplacer avant `running`. 

---

# v4 — finitions « îlots », quatre groupes, clics garantis (2026-10-31, soir)

Brief : `docs/BRIEF-rin-barre-v4.md`. **Session sans aucune action système**
(momo travaillait) : lecture, `qmllint` Qt6, `bash -n`, `py_compile`, `git`,
calculs. Tout le dynamique est dans la checklist du rapport (redémarrage par
momo).

## Ce qui a changé

1. **Quatre groupes, une seule règle d'espace** (`shell.qml`). `ColumnLayout` +
   deux ressorts remplacés par un `Item` (`stack`) contenant quatre `Column`
   positionnées par arithmétique :
   `y(n+1) = y(n) + h(n) + Config.spacing + libre/3`, avec
   `libre = hauteur utile − Σ hauteurs − 3 × Config.spacing`. Chaque groupe
   garde sa hauteur naturelle → aucune pilule ne s'étire.
2. **Workspaces compacts** (`modules/Workspaces.qml`) :
   `implicitHeight = nbPoints × 13 + 2 × 4`. Fond de pilule ajouté (uniformité).
   Le `Repeater` est modélisé par un **nombre** (`points`), l'état de chaque
   point se lit par `infoAt(i)` : pas de reconstruction des délégués à chaque
   événement Hyprland.
3. **`bar.persistentWorkspaces`** (défaut 10, 0 = existants seuls) dans
   `Config.qml` + `bar.json`. Points inexistants : `alpha 0.18`, cliquables
   (`Hypr.goWorkspace(id)`), infobulle « inexistant (clic : y aller) ».
4. **Métriques communes** : `Config.caseH` (32) / `Config.pad` (4) /
   `Config.pillRadius` (12) / `Config.wsStep` (13). Horloge = 2 cases,
   volume = 3 cases (10 tirets de 5 px), toggles = 3 cases, débit = 1 case.
5. **`WheelZone` sans `MouseArea`** : `Item` + `WheelHandler` (voir piège 21).
   AppDock n'a plus de zone superposée du tout.
6. **Popups** : `Shortcut Escape` + `focusable` + `WlrKeyboardFocus.OnDemand`
   dans les sept surfaces ; `Ui.open()/close()` appellent `Tip.hideNow()`.
7. **Infobulle** : marge gauche = 8 px après la zone utile (ou
   `marginLeft + width + 8` si `exclusiveZone` est false), largeur max 300 px,
   `TextMetrics` pour éviter une largeur circulaire, retour à la ligne.
8. **`install.sh`** : waybar liée, jamais activée, arrêtée si active ; gardes de
   `theme-apply.sh` / `apply-lang.sh` vérifiées (grep, avertissement si absent).
   `theme-apply.sh` : le skip idempotent testait un waybar vivant → il teste
   maintenant un **quickshell** de l'instance Hyprland courante (`bar_current_session`).
9. **IPC** : `qs ipc call bar layout` → hauteurs/positions réelles des quatre
   groupes ; `bar state` expose `caseH`, `pillRadius`, `persistentWorkspaces`.

## Schéma vertical calculé (40 px, écran 1080, bar.json actuel)

| Groupe | hauteur | y local | y écran |
|---|---|---|---|
| haut (recherche 32 + 8 + workspaces 138) | 178 | 0 | 12 → 190 |
| info (débit 32 + 8 + horloge 64 + 8 + volume 96) | 208 | 238,67 | 250,7 → 458,7 |
| apps (épinglées 232 + 8 + en cours 112) | 352 | 507,33 | 519,3 → 871,3 |
| bas (toggles 96 + 8 + engrenage 32) | 136 | 920,00 | 932 → 1068 |

Hauteur utile 1056 px (1064 − 2 × 4), contenu 874 px, libre 158 px,
écart entre groupes = 8 + 52,67 = **60,67 px**. Aucune pilule ne contient de
vide : le libre est uniquement dans les trois écarts.

## Contrôles statiques
- `qmllint` Qt6 (`/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml`) sur les 33
  fichiers : **0 erreur** ; seuls les avertissements de style déjà présents
  (`unqualified`, `PanelWindow is not creatable`, singletons hors `qmldir`).
- `bash -n` : `install.sh`, `scripts/theme-apply.sh`, `scripts/apply-lang.sh`,
  `cc/bar/bar.sh`, `tests/*.sh`.
- `py_compile` : `cc/bar/appindex.py`, `cc/bar/barjson.py` (inchangés).

## Pièges v4 (à ne pas repayer)
18. **`pragma Singleton` manquant = shell mort.** Un fichier listé `singleton`
    dans `qml/qmldir` sans `pragma Singleton` ne se charge pas comme singleton :
    Quickshell sort au démarrage et systemd répète la relance jusqu'à
    `start-limit-hit` (barre absente, journal qui ne dit presque rien). Les huit
    singletons (`Config`, `BarPalette`, `Backend`, `AppIndex`, `PinWriter`, `Tip`,
    `Hypr`, `Ui`) portent le pragma — le vérifier avant d'en ajouter un.
19. **Borne basse d'alpha.** `optNum(..., "panelAlpha", 0.24, 0.02, 1.0)`
    ramenait `"panelAlpha": 0` de `bar.json` à **0.02** : une dalle fantôme sur
    toute la barre alors que le style est « îlots ». Les bornes de `panelAlpha`
    et `borderAlpha` sont maintenant `0.0`.
20. **`Config.hit` ≠ `Config.block`.** À 40 px, `block = 32` mais `hit` valait
    `max(38, block)` : les boutons ronds (loupe, engrenage) débordaient de 3 px
    de chaque côté de la colonne. `hit = block` ; `hitMin` (38) ne sert plus
    qu'aux popups.
21. **Un `MouseArea` de molette peut avaler un clic ; un `WheelHandler` non.**
    `acceptedButtons: Qt.NoButton` suffit tant que rien ne change de z-order,
    mais ce n'est pas une garantie structurelle. `WheelHandler` ne traite que
    l'événement de molette : il n'a aucun bouton à accepter.
22. **`Repeater` modèle = tableau d'objets reconstruits = clignotement.** Un
    modèle recalculé à chaque événement Hyprland détruit et recrée tous les
    délégués (animations relancées, `Ui.track` churn). Modéliser par un
    **nombre** et lire l'état par fonction (`infoAt(i)`).
23. **Marges d'une surface layer = zone UTILE, pas l'écran.** Mesuré en v1 :
    avec 62 px réservés, `margins.left: 72` plaçait la surface à 134 px. D'où
    l'infobulle : `left: 8` quand la barre réserve sa place, sinon
    `marginLeft + width + 8`.
24. **`Shortcut` n'existe que dans une fenêtre qui a le focus clavier.** Échap
    ferme les popups parce qu'elles sont `focusable` + `OnDemand` (pas un grab) :
    sans focus, aucun raccourci n'est délivré à une surface layer.

