# cc/bar — barre Quickshell (remplace waybar)

Barre de **40 px** écrite en **Quickshell 0.3.2**, placée au choix **à gauche,
en haut ou à droite** (`bar.position`), palette générée depuis le wallpaper via
le backend du Control Center (`http://127.0.0.1:8765`), configuration
versionnée dans `bar.json`, toggle **Super+J**.

**Aucun fond (v5b)** : `panelAlpha` **0** (pas de dalle), `blockAlpha` **0**
(pas de pilule opaque) et `blur` **false** (aucune bande floutée). Sur le
bureau, on ne voit **que les glyphes et les textes** des modules. L'affordance
reste : au survol (ou à l'état actif) une pilule légère apparaît
(`hoverAlpha` 0.16 / `activeAlpha` 0.30), et la zone cliquable ne change pas
(≥ 38 px pour les surfaces de popups, `Config.block` pour un bloc de barre).

```
quickshell -p ~/.config/cc/bar/shell.qml     # lancement direct
~/.config/cc/bar/bar.sh                      # toggle (Super+J)
systemctl --user start sasquatch-bar         # mode service
```

---

## 1. Ce que montre la barre (de haut en bas)

Quatre groupes (v4) : **haut** · **info** · **apps** · **bas**. Chaque groupe
prend sa hauteur naturelle ; l'espace libre est réparti **entre** les groupes,
jamais dans une pilule.

| Groupe | Module | Ce qu'il fait |
|---|---|---|
| haut | `search` | loupe → **lanceur du dotfile** `~/.config/rofi/scripts/launcher.sh` (thème `sasquatch.rasi`, mode combi apps+calc) par `hyprctl dispatch exec` ; repli `rofi -show drun -theme …` ; état « lanceur introuvable » visible |
| haut | `workspaces` | points verticaux **compacts** (hauteur = nb points × 13 + 8 px), actif = trait 3×11 px ; `persistentWorkspaces` affiche aussi les workspaces inexistants (point atténué, **cliquable**) ; clic = aller au workspace ; **une seule zone de molette** sur tout le bloc ; infobulle = nb de fenêtres |
| info | `netRate` | débit ↑/↓ (Ko/s du backend, formaté B/K/M) ; clic = popup réseau |
| info | `clock` | HH / mm / AM-PM + icône calendrier ; clic = calendrier ; infobulle = date longue + jour japonais |
| info | `volume` | slider vertical en 12 tirets ; molette = ±5 % ; clic = popup volume/luminosité ; muet = icône |
| apps | `pinnedApps` | apps de `bar.json.apps` ; badge = nb de **fenêtres** ; état ouvert visible (barre d'accent + halo + contour) ; clic = **aller sur la fenêtre** (workspace compris) sinon lancement ; molette = fenêtre suivante/précédente ; **clic droit = menu (Détacher / Fenêtres)** ; clic milieu = fenêtres ; bouton **« + »** en bas = épingler une app |
| apps | `runningApps` | fenêtres groupées par classe (hors apps épinglées), **fenêtre glissante de 3** ; molette = fait défiler la liste ; clic = aller sur la fenêtre ; clic droit = menu (Épingler / Fenêtres) ; clic milieu = fenêtres |
| bas | `quickToggles` | son (mute) · réseau (popup) · DND (`makoctl`) ; 3 cases de 32 px dans une seule pilule ; actif = fond accent + contour d'accent |
| bas | `settings` | engrenage → **Sasquatch Settings** (`~/.config/settings/settings.sh`, backend 8770, Super+I). Le Control Center reste accessible ailleurs (Super+E / rofi), ce n'est plus ce bouton. |

Chaque module a un **état d'erreur visible** (glyphe + infobulle
« indisponible ») quand la donnée manque : jamais un blanc, jamais un crash.

Popups (une surface chacune, une seule ouverte à la fois) : calendrier,
volume + luminosité, réseau (iface, IP, débits, historique 30 points),
notifications (historique mako), liste des fenêtres.

---

## 2. `bar.json` — toutes les clés

Le fichier est **surveillé à chaud** (`FileView` + `watchChanges`). Un JSON
invalide est ignoré : la dernière configuration valide reste active et un point
rouge apparaît en bas de la barre (infobulle = message d'erreur). Chaque clé
absente prend son défaut **dans le code** (`qml/Config.qml`).

```json
"bar": {
  "enabled": true,        // false = barre masquée (surface détruite)
  "position": "left",     // left | top | right — HONORÉ par la barre (v5b)
  "width": 40,            // ÉPAISSEUR de la barre en px (32-240), quel que soit le bord
  "marginTop": 8,         // marge haute (écran)
  "marginBottom": 8,      // marge basse (positions verticales)
  "marginLeft": 6,        // marge gauche = écart au bord de l'écran
  "marginRight": 6,       // marge droite (utilisée en position "right")
  "exclusiveZone": true,  // true = réserve largeur + marge (dock)
  "radius": 14,           // rayon des coins de la barre
  "spacing": 8,           // espace UNIQUE entre blocs ET base des écarts entre groupes
  "blockInset": 4,        // marge latérale d'un bloc : bloc = width - 2*inset
  "blur": false,          // false = AUCUN flou derrière la barre (défaut v5b)
  "blurRadius": 10,       // rayon du flou si blur = true (≤ 10 : voile laiteux)
  "persistentWorkspaces": 10  // nb de points de workspace affichés (0 = existants seuls)
},
"modules": [ ... ],       // liste ordonnée, voir §3
"clock": {
  "hourFormat": "HH",     // format Qt de l'heure
  "minuteFormat": "mm",
  "period": "AP",         // "AP" = AM/PM ; "ap"/"" pour masquer
  "calendarIcon": true
},
"apps": [
  { "id": "spotify", "desktop": "spotify.desktop", "class": "Spotify", "enabled": true }
],
"popups": { "calendar": true, "volume": true, "network": true, "notifications": true },
"appearance": {
  "panelAlpha": 0.0,       // dalle de barre : 0 = AUCUN fond
  "blockAlpha": 0.0,       // pilule AU REPOS : 0 = seuls les glyphes se voient
  "cardAlpha": 0.99,       // surface des POPUPS (elles restent lisibles)
  "hoverAlpha": 0.16,      // pilule au SURVOL (léger, paletté)
  "activeAlpha": 0.30,     // état actif sur l'accent (popup, mute, app ouverte)
  "borderAlpha": 0.0,      // bordure du panneau (0 = pas de bordure)
  "borderHoverAlpha": 0.18,// bordure de pilule, AU SURVOL uniquement
  "iconSize": 15,          // glyphes Nerd Font
  "appIconSize": 19,       // icônes d'application
  "clockSize": 15,         // chiffres de l'horloge (jamais < 14)
  "netSize": 9             // débit réseau (jamais < 9)
}
```

- `exclusiveZone` réserve l'**épaisseur** (`bar.width`) du côté ancré : gauche
  ou droite en vertical, haut en position `top`. Vérification :
  `hyprctl layers | grep -A3 sasquatch-bar` puis `hyprctl monitors -j`
  (`reserved[0]` = **46** pour width 40 + marginLeft 6).
- `appearance.panelAlpha` / `blockAlpha` / `hoverAlpha` / `activeAlpha` sont des
  **opacités** appliquées à la palette (`alpha(bg, .24)`, `alpha(card, .16)`…).
  Aucune couleur n'est écrite dans le JSON : elles viennent toutes de
  `GET /api/palette`. Les icônes et le texte restent à 100 % d'opacité.
- `appearance.blockAlpha` (v5b) : fond d'une pilule **au repos**. À **0** la
  barre est invisible sur le wallpaper — `panelAlpha` 0 ne suffisait pas, les
  pilules restaient opaques. Monter à 0.10-0.20 si on préfère des îlots
  visibles. `cardAlpha` ne concerne plus que les popups.
- `bar.blur: false` (v5b) : `BackgroundEffect` reçoit un rayon **0**, donc plus
  aucune bande floutée sur la hauteur de la barre. Le `Rectangle id: barBg`
  reste déclaré (il porte la `Region` du flou et la région d'entrée) et prend
  `color: "transparent"` ; le supprimer ferait tomber les clics à travers.
- `bar.width` et `bar.blockInset` déterminent la taille de TOUS les blocs :
  `Config.block = width - 2*inset` (**40 → 32 px**), et la cible cliquable d'un
  bloc vaut `Config.block` (voir §9). Aucune taille de bloc n'est codée dans
  les modules.
- `persistentWorkspaces` : **10** = dix points fixes (comme l'ancienne waybar),
  les workspaces inexistants sont atténués mais cliquables ; **0** = seulement
  les workspaces existants (comportement v3). Rechargement à chaud.

---

## 3. Ajouter / retirer / réordonner un module

`modules` est une liste ordonnée. Les noms reconnus :
`search`, `workspaces`, `netRate`, `clock`, `volume`, `pinnedApps`,
`runningApps`, `quickToggles`, `settings`.

- **Retirer** un module : enlever son nom de la liste (rien d'autre).
- **Réordonner** : changer l'ordre ; l'ordre est respecté **à l'intérieur de
  chaque groupe** (haut / info / apps / bas). Le groupe est fixé dans
  `shell.qml` (`zones`) : c'est la mise en page (4 groupes, v4 §2), pas une
  préférence utilisateur.
- Un nom inconnu est ignoré avec un `console.warn` (la barre ne casse pas).

---

## 4. Ajouter / détacher une application

**Depuis la barre (le plus simple, v3)** : bouton **« + »** sous les apps
épinglées → popup « Ajouter une application » (champ de recherche sur les
apps **installées**, source `appindex.py --json`) → clic = épinglage, la barre
se recharge à chaud. **Clic droit** sur une app épinglée = « Détacher » ;
**clic droit** sur une app en cours = « Épingler ».

L'écriture passe par `barjson.py` (jamais un `JSON.stringify` QML) :

- réécriture **atomique** (fichier temporaire + `rename`) ;
- **indentation et ordre conservés**, seule la section `apps` bouge (le reste
  du fichier est recopié octet pour octet, vérifié avant écriture) ;
- une app déjà épinglée est **réactivée** (`enabled: true`), jamais dupliquée ;
- fichier en lecture seule ou JSON invalide → message explicite, **aucune
  écriture partielle**.

**À la main**, c'est la même structure :
1. Ajouter une entrée dans `apps` :
   ```json
   { "id": "thunderbird", "desktop": "thunderbird.desktop", "class": "thunderbird", "enabled": true }
   ```
   - `desktop` = nom du fichier `.desktop` (l'icône et la commande en viennent) ;
   - `class` = classe Hyprland de la fenêtre (`hyprctl clients -j`) : c'est
     elle qui compte les fenêtres et évite le doublon dans `runningApps`.
2. Rien à relancer : le fichier est rechargé à chaud.
3. Vérifier l'icône résolue :
   ```bash
   python3 ~/.config/cc/bar/appindex.py --json | jq '.apps["thunderbird"]'
   ```

---

## 5. Changer la largeur

`"width": 46` dans `bar.json` → la barre et la zone réservée suivent
immédiatement (aucun redémarrage). Les marges restent `marginTop/Bottom/Left`,
et `Config.block = width - 2*blockInset` (soit 38 px à 46, 32 px à 40) : les
pilules, les glyphes et les points de workspace suivent sans retouche.

À **40 px**, la cible cliquable d'un bloc fait 32 px : c'est le prix de
« rien ne dépasse de la colonne » (voir §9).

---

## 5b. Changer de position : Gauche / Haut / Droite

`bar.json` → `"position": "left" | "top" | "right"`. **Le réglage est
réellement appliqué** (la barre se recharge en < 2 s) :

| `position` | Ancrages de la surface | Géométrie | Groupes |
|---|---|---|---|
| `left` | gauche + haut + bas | largeur `bar.width`, pleine hauteur, `marginLeft` | 4 `Column` empilées |
| `top` | haut + gauche + droite | **hauteur `bar.width`** (même épaisseur), pleine largeur, `marginTop` | 4 `Row` alignées (mêmes modules, même ordre) |
| `right` | droite + haut + bas | largeur `bar.width`, pleine hauteur, `marginRight` | 4 `Column` empilées (ordre inchangé) |

- **Une seule** `PanelWindow` dans les trois cas : on déplace la surface, on
  n'en crée jamais une seconde. `exclusiveZone` = l'épaisseur, jamais animée.
- En `top`, chaque module rend sa variante « une ligne » (l'horloge affiche
  `HH:mm`, les workspaces passent en points horizontaux, le volume en tirets
  horizontaux, les apps en rangée) : `Config.horizontal` pilote tout, aucune
  duplication de module.
- Les **popups** et l'**infobulle** s'ouvrent du côté de la barre (gauche /
  droite) et **sous** elle en `top` — sinon elles apparaîtraient à l'opposé.
- Par le panneau Settings : section **BARRE**, trois boutons **Gauche / Haut /
  Droite**. L'état affiché est **relu depuis le disque** (`GET /api/bar`, puis
  `res.state` après chaque écriture) ; un clic part en `POST /api/bar` →
  `barjson.py --set bar.position=…`, qui ne change **que** cette clé.
- En ligne de commande (même chemin d'écriture) :

```bash
~/.config/cc/bar/barjson.py --set bar.position=top
qs -i <id> call bar state | jq '{position, horizontal}'   # ce que la barre applique
qs -i <id> call bar layout | jq '.groups[] | {name, x, w}' # groupes en ligne
```

`barjson.py --set` refuse tout ce qui n'est pas `left|top|right`
(`SET_BOUNDS`), et `settings.py` refuse aussi la valeur avant d'appeler le
writer : un fichier édité à la main avec `"position": "bottom"` retombe sur
`left` (défaut de `Config.qml`), donc jamais de barre fantôme.

---

## 6. Dépannage — « la barre n'est pas là »

Dans cet ordre :

```bash
pgrep -x quickshell -a                    # le processus tourne-t-il ?
~/.config/cc/bar/bar.sh                   # relancer (toggle)
hyprctl layers | grep -A3 sasquatch-bar   # la surface existe-t-elle ? (xywh)
hyprctl monitors -j | jq '.[0].reserved'  # zone réservée : doit valoir [46,…]
journalctl --user -u sasquatch-bar -n50   # mode service
curl -s localhost:8765/api/palette | jq . # backend CC vivant ?
```

Cas connus :

| Symptôme | Cause | Correctif |
|---|---|---|
| barre transparente / texte invisible | backend 8765 mort → couleurs de secours | `systemctl --user start sasquatch-cc` |
| `qmllint` OK mais rien à l'écran | `bar.json` invalide → config précédente | lire le point rouge en bas de barre (survol) |
| fenêtres maximisées sous la barre | `exclusiveZone: false` dans `bar.json` | remettre `true` |
| icône d'app vide | `.desktop` introuvable pour cette classe | `appindex.py --json | jq '.classes'` |
| double barre (waybar + barre) | waybar encore active | `systemctl --user stop waybar` (voir §8) |
| pilules invisibles sur un wallpaper sombre | `blockAlpha` (repos) trop bas pour ce fond | monter `blockAlpha` (0 → 0.1) ou `hoverAlpha` |
| pas de flou | `decoration:blur:enabled` à 0 | `hyprctl getoption decoration:blur:enabled` |

---

## 7. Fichiers

```
cc/bar/
├── shell.qml         point d'entrée : barre + infobulle + popups + IPC
├── bar.json          configuration versionnée
├── bar.sh            toggle Super+J (détection par processus)
├── bar.service       unité systemd user (Restart=on-failure)
├── appindex.py       index .desktop (--json) et lancement (--launch <id>)
├── barjson.py        épingler/détacher : réécriture atomique de `apps` seule
├── qml/              singletons Config/BarPalette/Backend/AppIndex/Hypr/Ui/Tip
│                     + PinWriter (écriture de bar.json)
│                     + composants Pill, BarIcon, IconButton, AppIcon, Badge,
│                       HitButton (cible 38 px des popups), WheelZone
│                       (zone de molette plein bloc : `WheelHandler`, aucun
│                       MouseArea, donc aucun clic ne peut être avalé)
├── modules/          un fichier par module (9)
├── popups/           Calendar, Volume, Network, Notifications, Windows,
│                     AddApp (« + »), AppMenu (clic droit)
├── tests/            run-all.sh (qmllint + probes + IPC)
│                     verify-v2.sh (preuves du brief polish : clic app, boutons,
│                     alphas, centrage, engrenage)
└── reference/        barre-ref.png (référence visuelle)
```

- **Un seul timer de données** (`qml/Backend.qml`, 2 s) + le timer de palette
  (2 s, exigé par le brief) + `SystemClock` pour l'heure. Aucun module n'a de
  timer.
- **Un seul point HTTP** : `qml/Backend.qml` (stats, volume, luminosité) et
  `qml/BarPalette.qml` (palette). Les POST passent par `Backend`.
- **IPC** (utile pour tester sans souris) :
  ```bash
  qs -i <id> call bar popup calendar     # ou volume|network|notifications|windows
  qs -i <id> call bar close
  qs -i <id> call bar reload             # relit bar.json
  qs -i <id> call bar state              # JSON d'état (modules, alphas, volume, pinnedOpen…)
  qs -i <id> call bar rects              # géométrie de CHAQUE cible cliquable
  qs -i <id> call bar layout             # hauteurs + positions des 4 groupes (v4)
  qs -i <id> call bar wheels             # géométrie de CHAQUE zone de molette
  qs -i <id> call bar action <nom>       # exécute le code exact d'un bouton
  qs -i <id> call bar focusApp <classe>  # même chemin qu'un clic d'app
  qs -i <id> call bar clickApp <id>      # idem pour une app épinglée de bar.json
  qs -i <id> call bar cycleApp <classe> <±1>
  qs -i <id> call bar pinApp <id>        # épingler (même code que la popup « + »)
  qs -i <id> call bar unpinApp <id>      # détacher (même code que « Détacher »)
  qs -i <id> call bar addApp             # ouvre la popup « Ajouter une app »
  qs -i <id> call bar windows | clicks   # diagnostic (toplevels, journal des clics)
  ```
  `qs` = `quickshell ipc` ; `<id>` = `pgrep -x quickshell`.

---

## 8. Waybar : retirée (v4 — plus jamais activée)

La barre verticale remplace waybar depuis **2026-10-31**. Depuis la v4,
`install.sh` **ne l'active plus jamais** : il **lie** l'unité (le fichier reste
dans `~/.config/systemd/user/`), il **l'arrête si elle tourne**, et il vérifie
que `scripts/theme-apply.sh` et `scripts/apply-lang.sh` gardent leur garde
(ces deux scripts étaient les lanceurs de waybar au login et à chaque
changement de wallpaper — c'est ce qui la faisait « revenir »).

État attendu de la machine :

```
systemctl --user is-enabled waybar        → linked      (unité présente, AUCUN démarrage auto)
systemctl --user is-active  waybar        → inactive
systemctl --user is-enabled sasquatch-bar → alias       (unité liée : sasquatch-bar est un alias de bar.service)
systemctl --user is-active  sasquatch-bar → active
systemctl --user list-unit-files | grep -E "waybar|sasquatch-bar"
```

`bar.service` utilise `WantedBy=default.target` comme `sasquatch-cc` et
`sasquatch-sidebar` : sur ce poste `graphical-session.target` n'est **pas**
actif (Hyprland n'est pas câblé dessus), un `WantedBy=graphical-session.target`
ne démarrerait donc jamais la barre.

### Retour arrière (commandes exactes)

```bash
# 1. revenir à waybar seule (une seule ligne, la barre verticale s'arrête)
systemctl --user enable --now waybar && systemctl --user stop sasquatch-bar

# 2. revenir à la barre verticale (annule le 1)
systemctl --user disable waybar && systemctl --user start sasquatch-bar
```

Si le fichier d'unité a disparu (un `disable` malheureux, ou `~/.config`
nettoyé) :

```bash
ln -sf ~/Downloads/Sasquatch-Dotfile/waybar/waybar.service ~/.config/systemd/user/waybar.service
systemctl --user daemon-reload
```

Le binding Super+J pointe sur `~/.config/cc/bar/bar.sh` dans
`hypr/keybinds.conf` (l'ancienne ligne `waybar-toggle.sh` est commentée avec la
date). Waybar reste installée et sa configuration intacte : rien n'est supprimé
dans `waybar/`.

---

## 9. Écarts assumés par rapport au brief

1. **Popups en `PanelWindow` ancrées** et non en `FloatingWindow` : une
   `FloatingWindow` est une vraie fenêtre (elle entre dans `hyprctl clients`,
   prend le focus, demande des `windowrule`). Une surface layer par popup,
   `exclusiveZone: 0`, layer `overlay`, donne le même résultat sans toucher à
   la pile de fenêtres — et respecte la règle « une surface par popup, jamais
   une surface qui grandit ».
2. **`fillMode: PreserveAspectFit`** pour les icônes d'app (et non
   `PreserveAspectCrop`) : la règle du brief vise « une image ne détermine
   jamais la taille » (respectée : 22×22 fixes), et rogner une icône
   d'application la rend illisible.
3. **Débit réseau compact** (`↑1,2M`) dans la barre : 40 px de large ne
   contiennent pas `↓ 1,2 Mo/s`. La forme longue (`↑ 1,2 Mo/s`) est dans
   l'infobulle et dans la popup réseau.
4. **Groupes (haut/info/apps/bas)** : `modules` pilote l'ordre **dans** chaque
   groupe ; le groupe est fixé dans `shell.qml` (v4 §2 : recherche + points en
   haut, débit + horloge + volume au milieu, apps ensemble, toggles + engrenage
   en bas).
4bis. **Cible cliquable = 32 px, pas 38.** À 40 px de large, `Config.block`
   vaut 32 : une cible de 38 px déborderait de 3 px de chaque côté de la
   colonne (c'était le cas en v3, invisible mais réel). La règle « la zone
   cliquable couvre exactement la zone visuelle » est conservée ; seuls les
   boutons des **popups** gardent 38 px (`Config.hitMin`). Contrepartie : pour
   élargir la barre, `"width": 46` suffit (bloc 38).
5. **Notifications** : pas de `NotificationServer` QML (mako possède
   `org.freedesktop.Notifications`) → la popup lit `makoctl history -j`.
6. **`ram.pct`** n'est affiché par aucun module de la v1 : il n'y a donc pas
   de valeur RAM à l'écran à croiser (voir le rapport de livraison).

## 10. Tour de polish (2026-10-31, après rin)

Corrections appliquées après relecture du code livré :

1. **`bar.sh` ne lance plus `quickshell` en direct : il pilote le service**
   (`systemctl --user start/stop sasquatch-bar`, orphelins tués à part).
   Avant, un seul Super+J sortait la barre de systemd : plus de
   `Restart=on-failure`, plus de reprise au login, et un risque de double
   instance (service + lancement manuel). Vérifié : OFF → `reserved [0,0,0,0]`,
   ON → `reserved [62,0,0,0]`, un seul processus.
2. **Icône d'application non résolue = pastille avec l'initiale** (fond
   `accentSoft`, 22×22) au lieu d'un glyphe « inconnu » qui rendait un carré
   vide. Les classes sans `.desktop` (jeux Wine : `plariumplay.exe`,
   `raid.exe`, `explorer.exe`) passent par `AppIndex.pretty()` : plus jamais
   `explorer.exe` affiché tel quel, mais `Explorer`.
3. **App épinglée absente** : `appindex.py --launch` prévient désormais
   (`notify-send` + stderr, code 2) au lieu d'échouer en silence.
4. **`bar.json` : `vlc` → `org.kde.dolphin`** — VLC n'est pas installé sur ce
   poste, la pastille « V » était morte. À changer librement (§4).
5. **Apps en cours : `maxVisible` 3 → 4** (au-delà, pastille « +N »).
6. **`BarPalette.accentSoft`** ajouté comme token dérivé (`accent` à 0.22) :
   aucune nouvelle couleur en dur.

Contrôles rejoués après ces corrections : `qmllint` 28/28 sans sortie,
`bash -n` sur `bar.sh`, `py_compile` sur `appindex.py`, suite
`tests/run-all.sh` verte, rechargement à chaud de `bar.json` (56→64 px sans
redémarrage, JSON cassé = config précédente conservée), toggle Super+J
aller-retour.

## 11.0 Polish v2 — ce qui a changé (2026-10-31)

1. **Clic sur une app = aller sur la fenêtre.** La v1 rejouait une adresse lue
   dans un cache : (a) `HyprlandToplevel.address` n'a pas le préfixe `0x` que
   Hyprland exige (`No such window found`), (b) ce cache ne suit pas les
   changements de focus. Le clic lit maintenant `hyprctl clients -j` au moment
   du clic (une exécution, aucun timer), prend la fenêtre au `focusHistoryID`
   le plus bas, dispatche `workspace <ws>` puis `focuswindow address:0x…`, et
   rejoue une seule fois si l'adresse a disparu entre-temps.
2. **Boutons.** Cible 38 × 38 pour toutes les pilules et tous les glyphes de
   la barre (loupe, débit, horloge, volume, apps, toggles, engrenage), et
   38 × 38 pour chaque commande de popup (fermer, mois ±1, corbeille). La zone
   cliquable est **exactement** le rectangle dessiné (mesuré : `hitMatchesVisual`
   vrai partout). Une cible absente (app inconnue, rofi manquant, fenêtre
   fermée pendant le clic) déclenche une notification `notify-send` ET une
   ligne dans `clicks`.
3. **Transparence.** `panelAlpha` 0.75 → 0.24, `cardAlpha` 0.55 → 0.20,
   `hoverAlpha` 0.35, `borderAlpha` 0.12 ; bordure de pilule au survol
   seulement. Texte et icônes restent opaques. Flou demandé avec `radius 10`
   (aucun voile laiteux constaté).
4. **Finesse.** Barre 56 → 46 px, blocs 38 px (`width - 2*blockInset`),
   glyphes 16 px, icônes d'app 20 px, chiffres d'horloge 15 px, débit 9 px.
   Texte en `Text.NativeRendering` (l'AA sous-pixel faisait des franges
   colorées sur surface translucide).
5. **Centrage.** Un seul `ColumnLayout` racine (groupe haut, ressort, groupe
   centre, ressort, groupe bas), groupes imbriqués centrés par
   `Layout.alignment: Qt.AlignHCenter`. Mesure `rects` : x=4, w=38, centre=23
   pour les 25 cibles (= 46/2). Corrigé aussi un recouvrement de 11 px entre
   le dernier point de workspace et le bloc débit.
6. **Engrenage → Sasquatch Settings** (`~/.config/settings/settings.sh`,
   backend 8770), infobulle « Réglages (Super+I) ». Le Control Center n'est
   plus derrière ce bouton (il reste accessible par son propre raccourci).

## 11. Décisions laissées à momo

- **Workspaces** : TRANCHÉ en v4 — `"persistentWorkspaces": 10` est dans
  `bar.json` (comme l'ancienne waybar : 10 points fixes, les inexistants sont
  atténués et cliquables). Mettre `0` revient au comportement v3 (seulement les
  workspaces existants). Rechargement à chaud, aucune redémarrage.
- **Fermeture des popups au clic extérieur** : toujours pas de clic-extérieur
  GLOBAL (aucun grab de compositor, c'est ce qui avait bloqué hyprlock). En v4 :
  Échap ferme, un clic sur une **zone vide de la barre** ferme, un clic sur un
  autre module ferme le précédent (un seul popup à la fois).
- **Notifications** : la popup lit l'historique mako ; pas de centre de
  notifications propre à la barre.
- **Points de workspace** : bande de **32 × 13 px** par point (v4 : pas de 13,
  point 11 px max) — 10 points = 138 px de pilule au lieu de 180. Réduire
  `persistentWorkspaces` raccourcit la pilule d'autant.
- **Apps en cours visibles** : 3 visibles, le reste par la **molette** (v3),
  sans indicateur de position (supprimé à la demande de momo le 2026-10-31).

## 12. v3 (2026-10-31, soir) — correctifs et épinglage depuis la barre

1. **Loupe = lanceur du dotfile.** `modules/Search.qml` appelle
   `hyprctl dispatch exec ~/.config/rofi/scripts/launcher.sh` (thème
   `sasquatch.rasi`, combi apps+calc, PATH qalc). Repli explicite
   `rofi -show drun -theme <thème>` si le script manque ; si les deux manquent,
   glyphe chaud + point d'alerte + infobulle « Lanceur introuvable » (sondes
   `test -x` au démarrage, aucun timer). Infobulle : « Rechercher (Super) ».
2. **Zones de molette.** Une zone par module, sur tout le bloc : workspaces
   (précédent/suivant, un seul `MouseArea` — plus de trou entre deux points),
   apps épinglées (fenêtre suivante/précédente, `Hypr.cycleApp` repart de la
   classe réelle), apps en cours (**défilement** de la liste, fenêtre
   glissante + piste/curseur), volume (±5 %). `bar wheels` publie le rectangle
   de chaque zone ; `WheelZone.qml` ne prend ni clic ni survol
   (`acceptedButtons: Qt.NoButton`) et les icônes renvoient leur molette au
   même gestionnaire → une seule action par geste.
3. **Épingler/détacher depuis la barre.** Bouton « + » → popup
   `AddAppPopup` (recherche sur `appindex.py --json`) ; clic droit sur une app
   épinglée → « Détacher », sur une app en cours → « Épingler » (popup
   `AppMenuPopup`, qui garde « Fenêtres »). Écriture par `barjson.py`
   (atomique, seule la section `apps` bouge, indentation/ordre conservés,
   réactivation au lieu de doublon, refus explicite si lecture seule/invalide).
4. **État actif.** `Hypr.countOfApp(cls, desktop)` normalise des DEUX côtés
   (`norm`) et ajoute l'id `.desktop` comme seconde clé. Rendu visible : barre
   d'accent latérale 3 × 22, halo `accentSoft`, `blockActive` remonté à 0.46
   (au lieu de 0.34 face à un panneau à 0.24) + contour d'accent.
   `bar state` expose `pinnedOpen: {id: bool}`.
5. **Centrage des glyphes.** `BarIcon` centre désormais **l'encre** du glyphe,
   pas son avance : dans une police monospace, un glyphe Nerd Font large
   (wifi U+F1EB : 19 px d'encre pour 9,59 px d'avance à 16 px) partait de
   4,7 px vers la droite. Table de compensation par glyphe (mesurée sur
   `JetBrainsMonoNerdFont-Regular.ttf`, voir l'en-tête de `qml/BarIcon.qml`),
   appliquée en `horizontalCenterOffset` / `verticalCenterOffset` et mise à
   l'échelle avec `appearance.iconSize`. Débit réseau : −1 px explicite.
6. **Contraintes tenues** : aucune couleur en dur hors `BarPalette`, aucun
   grab clavier global (la popup « + » prend le focus clavier **seulement
   pendant qu'elle est ouverte**, `WlrKeyboardFocus.OnDemand`), `bar.sh` pilote
   toujours `systemctl --user`, JSON cassé = config précédente conservée.

## 13. v4 (2026-10-31, soir) — finitions « îlots », quatre groupes, clics garantis

1. **Rythme vertical.** La barre est répartie en **quatre groupes** (haut :
   recherche + workspaces · info : débit + horloge + volume · apps : épinglées
   + « + » + en cours · bas : son/wifi/DND + engrenage). Chaque groupe prend sa
   **hauteur naturelle** ; le libre est réparti **à parts égales entre les
   groupes** (`écart = Config.spacing + libre/3`). Une seule règle, donc plus de
   grand vide au-dessus des apps et plus de pilule étirée.
2. **Pilule des workspaces compacte.** Hauteur = `nbPoints × 13 + 2 × 4`
   (10 points → **138 px**), points serrés, fond de pilule comme les autres
   blocs. `qs ipc call bar layout` publie les hauteurs/positions réelles.
3. **Uniformité.** Un seul rayon (`Config.pillRadius` = 12 à 40 px), un seul
   padding (`Config.pad` = 4 px), une seule hauteur de case (`Config.caseH` =
   32 px) : horloge = 2 cases, volume = 3 cases, toggles = 3 cases, débit = 1.
   Glyphes : toujours la table de compensation d'encre de la v3 (`BarIcon`).
4. **Densité 40 px.** La cible cliquable d'un bloc vaut `Config.block` (32 px,
   plus 38 qui débordait) ; la pastille de comptage passe à 12 px et reste
   **dans** le bloc ; le débit a 3 px d'air en haut et en bas.
5. **Aucun clic avalé par une zone de molette.** `qml/WheelZone.qml` n'est plus
   un `MouseArea` mais un **`WheelHandler`** : il ne traite que la molette, donc
   il ne peut pas intercepter un appui. Les apps épinglées n'ont plus de zone
   superposée du tout (la molette est sur le `MouseArea` de chaque icône).
6. **Popup « + »** : focus clavier à l'ouverture, Échap ferme, Entrée prend le
   premier résultat, **aucun grab** (`WlrKeyboardFocus.OnDemand`).
7. **Popups** : Échap ferme (raccourci de la fenêtre), clic sur zone vide de la
   barre ferme, un seul popup à la fois.
8. **Infobulle** : décalée à droite de la barre (marge = 8 px après la zone
   réservée, ou `marginLeft + width + 8` si `exclusiveZone` est false), largeur
   max 300 px, retour à la ligne, disparaît au clic.
9. **`bar.persistentWorkspaces`** (défaut 10, 0 = existants seuls) : points
   inexistants atténués **et cliquables**, à chaud.
10. **Contraste mesuré** (momo, wallpaper du soir) : pilule ≈ **rgb(42, 35, 41)**,
    texte `#d1d1d1` → **10,0 : 1** (AAA : ≥ 7). Pilule contre wallpaper sombre
    `#151515` → **1,19 : 1** : sur un fond sombre, l'îlot se lit par son bord et
    le flou, pas par le remplissage. Si les pilules disparaissent :
    `cardAlpha` 0.86 → 0.92 (seuil pratique : viser ≥ 1,3 : 1 avec le wallpaper).
