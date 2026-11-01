# BRIEF rin — Système de widgets Quickshell + refonte du CC (v1)

Destinataire : rin (agent d'exécution). Décisions déjà prises, ne pas les rediscuter.
Repo live : `~/Downloads/Sasquatch-Dotfile` (= `~/.config/{cc,hypr,waybar,rofi,kitty,mako,fastfetch}` via symlinks).
Backend : `sasquatch-cc.service`, `http://127.0.0.1:8765`. Quickshell 0.3.2 (Arch).

## 0. Faits VÉRIFIÉS sur cette machine — ne pas les re-tester, ne pas les contredire

1. **Le partage de code entre processus Quickshell passe par un VRAI module QML + `QML_IMPORT_PATH`.**
   Testé sur 0.3.2 :
   - `import "../widgets" as W` (dossier hors racine de config) → **BLOQUÉ** : `Type W.Hello unavailable` + `qrc:/qs-blackhole`.
   - `QML_IMPORT_PATH=<root> quickshell -p <host>` avec l'arborescence `<root>/Sasquatch/Widgets/qmldir` (`module Sasquatch.Widgets`) → **OK**, types statiques et singletons chargés.
   - `import qs.x` ne traverse pas deux configs : il est résolu depuis la racine de CHAQUE config.
   → donc : module `Sasquatch.Widgets` à `cc/widgets/Sasquatch/Widgets/`, et `QML_IMPORT_PATH="$HOME/.config/cc/widgets:$QML_IMPORT_PATH"` exporté par **chaque** lanceur.
2. `QML_IMPORT_PATH` (Qt6) et non `QML2_IMPORT_PATH`. Un `qmldir` déclarant un type `singleton` exige `pragma Singleton` dans le fichier, sinon le shell entier refuse de charger.
3. Ports/routes existants : `/api/palette`, `/api/stats`, `/api/music/status`, `/api/viz` (20 barres, 0..1), `/api/weather`, `/api/tasks`, `/api/sysinfo`, `/api/wallpaper*`, `/api/playlist/*`, `/api/tools/health`.
4. Formes exactes des payloads (ne pas deviner) :
   - `music/status` : `{source, player, playing, paused, title, artist, album, file, volume, elapsed, duration, art}` — `source ∈ mpris|mpd|pulse|web|none`.
   - `viz` : `{vals: [0..1] ×20, bars: 20}`.
   - `weather` : `{ok, city, temp, code, label, age_s}`.
   - `tasks` : `{items: [...], total, done}`.
   - `stats` : `{cpu, cores[], load[], ram:{used,total,pct}, gpu:{util,vram_used,vram_total,temp}, cpu_temp, net:{up,down,iface}, history:{cpu:[...]}}`.
   - `palette` : `{bg, bgSolid, card, cardSolid, text, textDim, accent, accent2, overlay, good, warn, hot}`.
5. Machine portable : `BAT0` existe. CC actuel : `FloatingWindow` plein écran, pages `home|sys|tools`, lancé par `cc/cc.sh` (`quickshell -p main.qml`, **pas** de service systemd pour l'UI).
6. La barre a déjà le pattern registre (`bar.json.modules` + map nom→fichier + un `Loader` par module). On généralise, on n'invente pas un deuxième système.

## 1. Arborescence cible (chemins exacts)

```
cc/widgets/Sasquatch/Widgets/          <- module (QML_IMPORT_PATH = ~/.config/cc/widgets)
    qmldir                             (module Sasquatch.Widgets + types + singletons)
    registry.json                      catalogue des widgets
    WidgetBase.qml                     base commune (MouseArea, drag, variantes, editing)
    WidgetHost.qml                     hôte générique (host + layout grid|free)
    WidgetCanvas.qml                   placement grid (CC) / free (background) + drag/resize
    WidgetRegistry.qml    [singleton]  lit registry.json, résout id -> composant + bornes
    Api.qml               [singleton]  XHR JSON vers 127.0.0.1:8765 (GET/POST, timeout, retry)
    Theme.qml             [singleton]  palette + tokens verre + texte adaptatif (lumgrid)
    Music.qml             [singleton]  poll /api/music/status (1 s) + /api/viz (60 ms, seulement si un cava est visible)
    Env.qml               [singleton]  météo (10 min) + stats (2 s) + tâches (5 s) + batterie
    widgets/MediaWidget.qml
    widgets/ClockWidget.qml
    ...                                (un fichier par widget)
cc/widgets.json                        instances (écrit PAR LE SERVEUR uniquement)
cc/widgets_json.py                     écrivain unique (patch, bornes, atomique, révision)
cc/background/shell.qml                hôte fond d'écran (1 PanelWindow layer Background par écran)
cc/background/background.sh            lanceur/toggle
cc/background/sasquatch-bg.service     unit user (Restart=always)
cc/widgets/tests/harness.qml           harnais de test 900x620 (jamais le CC plein écran)
cc/widgets/tests/run-all.sh            qmllint + tests API + tests de persistance
cc/pages/{HomePage,StudioPage,SystemPage,ToolsPage}.qml
```

## 2. Contrat d'un widget (obligatoire, identique pour les 16)

`WidgetBase.qml` = `MouseArea` (drag, curseur), API :

| prop | type | rôle |
|---|---|---|
| `instanceId` | string (required) | id de l'instance dans widgets.json |
| `host` | string (required) | `background|cc|bar|subpage` |
| `variant` | string (required) | `compact|normal|hero` |
| `editing` | bool (required) | mode Studio : drag actif, interactions internes coupées |
| `style` | var (required) | `{alpha, accent, blur, radius}` |
| `options` | var (required) | options fonctionnelles du widget (bornées par le registre) |
| `implicitWidth/implicitHeight` | real | taille naturelle PAR variante |
| `interactive` | bool | faux en `editing` et quand l'hôte est `background` hors édition |

Interdits : un widget ne connaît ni `main.qml`, ni la barre, ni le fond d'écran ; il ne fait aucun
`XMLHttpRequest` lui-même (il lit `Music`, `Env`, `Theme`). Aucune couleur en dur, aucun `width: 320`
littéral : les tailles dérivent de `style`/`variant` et de la grille de l'hôte.

Tailles naturelles (px) : `compact` 220×64 · `normal` 360×180 · `hero` 560×260 (sauf mention au registre).

## 3. Style — « affiné, épuré », verre léger (nombres imposés)

Tokens calculés depuis `Theme` (jamais de hex) :
`glassBase = Qt.lighter(bgSolid, 1.18)`, `glassCard = Qt.darker(card, 1.20)`, `glassBtn = Qt.darker(card, 1.55)`,
`border = rgba(accent, 0.35)`, `halo = rgba(accent, 0.32)`, `light = rgba(text, 0.12)` (1 px de haut).

| Part | alpha |
|---|---|
| panneau / board CC | 0.36 |
| carte / widget | 0.24 (défaut `style.alpha`) |
| hero (grand média / horloge) | 0.15 |
| boutons / pilules | 0.62 |
| bordure | 0.35 · halo actif 0.32 |

Rayons : panneau 18 · carte 14 · bouton 10. Espacement 14. Cible de clic ≥ 30 px, padding ≥ 10 px.
Blur : `BackgroundEffect.blurRegion: Region { item: fond }`, `radius: style.blur` (défaut 9). Blur = option,
toujours dégradable : si le protocole ne répond pas, le widget reste lisible sans (aucun crash, aucune exception).
Animation : `Easing.OutCubic` uniquement ; hover 90 ms, état actif 160 ms, entrée de carte 180 ms (+40 ms en cascade).
Texte qui déborde : `elide: Text.ElideRight`, jamais de retour à la ligne implicite.
Jamais de `font.family` en dur : la police du rice.

## 4. Registre + instances + écrivain unique

`registry.json` — une entrée par widget :
```json
{"widgets": [{
  "id": "media", "name": "Média", "component": "MediaWidget.qml",
  "hosts": ["background", "cc", "bar", "subpage"],
  "variants": {"compact": {"w": 220, "h": 64, "cell": [4, 1]},
               "normal":  {"w": 360, "h": 180, "cell": [4, 2]},
               "hero":    {"w": 560, "h": 260, "cell": [8, 2]}},
  "defaultVariant": "normal",
  "style": {"alpha": [0.10, 0.90], "blur": [0, 20], "radius": [0, 24],
            "accent": ["auto", "primary", "secondary", "text"]},
  "options": {"bars": {"type": "int", "min": 8, "max": 48, "default": 28},
              "showSource": {"type": "bool", "default": true}}
}]}
```
Le composant est résolu par `WidgetRegistry.component(id)` → `Qt.resolvedUrl("widgets/" + component)`.
Le chemin ne vient JAMAIS directement du JSON d'instances (seulement du registre, embarqué).

`cc/widgets.json` :
```json
{"version": 1, "revision": 7,
 "instances": [
  {"id": "media-main", "type": "media", "host": "cc", "variant": "hero",
   "geo": {"col": 0, "row": 0, "w": 8, "h": 2},
   "style": {"alpha": 0.24, "accent": "auto", "blur": 9, "radius": 16},
   "options": {"bars": 28, "showSource": true}},
  {"id": "clock-bg", "type": "clock", "host": "background", "variant": "hero",
   "geo": {"x": 0.62, "y": 0.08, "w": 420, "h": 200},
   "style": {"alpha": 0.15, "accent": "auto", "blur": 9, "radius": 16}, "options": {}}
 ]}
```
- `host: cc` → `geo` en **cellules** d'une grille 12 colonnes (row 96 px, gap 14).
- `host: background` → `geo.x`/`geo.y` en **fractions 0..1** de l'écran (robuste au changement de résolution), `w`/`h` en px ; on borne à l'écran au chargement.
- `host: bar|subpage` → `geo.slot` (entier d'ordre).

`cc/widgets_json.py` = **seul écrivain**. API : `get()`, `apply(op)` avec `op ∈ add|rm|move|resize|style|variant|option|reorder`.
Règles : valider `type` contre le registre, clamper chaque nombre sur les bornes du registre, refuser une clé
inconnue, incrémenter `revision`, écrire `widgets.json.tmp` + `os.replace()`, sérialisation 4 espaces.
Nouvelle révision = relecture obligatoire avant de répondre (`{"ok": true, "revision": N, "instance": {...}}`).

Routes à ajouter dans `cc/server.py` (une dizaine de lignes chacune, même style que l'existant) :
- `GET  /api/widgets` → `{"ok":true, "revision":N, "data":{...}}`
- `POST /api/widgets` body `{"op": "...", ...}` → passe par `widgets_json.apply` ; 400 explicite si invalide.
- `GET  /api/wallpaper/lumgrid` → `{"wallpaper": "<chemin>", "w": 32, "h": 18, "values": [0..1]}` calculé
  avec PIL (déjà utilisé ailleurs), cache par (chemin, mtime). Si PIL absent → `{"values": []}` et le thème
  garde son texte clair (jamais de crash).

## 5. Hôtes

**background** (`cc/background/shell.qml`) : `Variants { model: Quickshell.screens }` → un `PanelWindow` par écran,
`WlrLayershell.layer: WlrLayer.Background`, `exclusiveZone: 0`, `color: "transparent"`, `anchors` sur les 4 bords.
- **Input region = union des widgets uniquement** : `mask: Region { Region { item: w0 }, Region { item: w1 }, ... }`
  (Region imbriquées, défaut `Intersection.Combine`). Un widget non interactif ou `editing` laisse passer les clics.
- Hors mode édition, un widget `background` est **inerte** (`interactive: false`) sauf ceux dont le registre
  déclare `"live": true` (media, clock) → clic = ouvrir le CC, pas de transport sur le fond.
- Mode édition (`editing: true`) : drag + poignée de resize, contour 1 px accent, poignée 10 px en bas-droite ;
  écriture via POST (jamais en direct dans le fichier). Désactiver drag → poster `move` une seule fois au relâchement.
- Watcher : `FileView { path: ".../widgets.json"; watchChanges: true }` + lecture debouncée 150 ms + `revision` ignorée si identique. Un `os.replace` change l'inode : relire le fichier à chaque signal, ne pas garder un handle.

**cc** (`pages/HomePage.qml`) : board 12 colonnes, `row` 96 px, `gap` 14, `cell` → x/y/w/h calculés ;
`cellSpan` par variante depuis le registre. Pas de drag dans le CC en v1 (Studio gère).

**bar / subpage** : v1 = contrat respecté, `variant: compact` dans le harnais uniquement. Branchement réel en v1d,
et seulement si la place le permet (ne pas casser la barre validée).

## 6. Catalogue à livrer (16) — vagues

| # | id | Widget | Variantes | Hôtes | Vague |
|---|---|---|---|---|---|
| 1 | `media` | Média : pochette 96², titre/artiste, cava 28 barres, transport, pilule source (MPRIS/mpd/pulse) | compact (barre de son + play), normal, hero, `visualizer` (cava seul, pas de carte) | tous | v1b |
| 2 | `clock` | Horloge digitale / analogique / minimale | compact (HH:mm), normal (+ date), hero (+ secondes, analogique) | tous | **v1a** |
| 3 | `resources` | CPU/RAM/GPU + sparkline + températures | compact (3 anneaux), normal, hero | tous | v1d |
| 4 | `volume` | Volume + luminosité (2 lignes, micro inclus) | compact (1 slider), normal | cc, background, bar | v1d |
| 5 | `battery` | Charge, profil d'énergie, temps restant | compact, normal | cc, background, bar | v1d |
| 6 | `weather` | Maintenant + 3 jours | compact, normal, hero | tous | v1d |
| 7 | `tasks` | TODO (coche, ajout, total/done) | compact, normal | cc, background | v1d |
| 8 | `wallpaper` | Grille de vignettes + apply | normal | cc, background | v1d |
| 9 | `playlist` | File d'attente (MPD), lecture, remove | normal, hero | cc | v1d |
| 10 | `calendar` | Mois + events (tâches datées) | normal, hero | cc, background | v1d |
| 11 | `connectivity` | Réseau + BT + périphérique audio | compact, normal | cc, background, bar | v1d |
| 12 | `toggles` | DND, blur, night light, mode allégé | compact, normal | cc, background | v1d |
| 13 | `notifications` | 3 dernières + badge | compact, normal | cc, background | v1d |
| 14 | `workspaces` | Bureaux + fenêtres Hyprland | compact, normal | cc, background | v1d |
| 15 | `apps` | Favoris / mini-launcher (via `bar/appindex.py`) | compact, normal | cc, background | v1d |
| 16 | `notes` | Notes + presse-papier | normal | cc, background | v1d |

## 7. Slices — une seule à la fois, dans cet ordre

### v1a — socle + `clock` (le livrable de CE brief)
1. Module `Sasquatch.Widgets` complet : `qmldir` (+`pragma Singleton` sur les singletons), `WidgetBase`,
   `WidgetHost` (grid + free), `WidgetCanvas` (drag/resize), `WidgetRegistry`, `Api`, `Theme`, `Env` (horloge locale ok),
   `registry.json` avec **2 entrées** (`clock`, `media` — `media` déclarée mais `component` vide pour l'instant).
2. `cc/widgets_json.py` + `GET/POST /api/widgets` + `widgets.json` par défaut (1 horloge CC + 1 horloge fond).
3. `widgets/ClockWidget.qml` (3 variantes, secondes, analogique en `Canvas`/`Shape` — pas de dépendance externe).
4. `cc/background/shell.qml` + `background.sh` + `sasquatch-bg.service` (unit user, `Restart=always`, `WantedBy=default.target`).
5. Export `QML_IMPORT_PATH` ajouté dans `cc/cc.sh`, `cc/background/background.sh`, `subpage/subpage.sh`
   et `Environment=` de `cc/bar/bar.service` (une ligne chacune, chemin `%h/.config/cc/widgets`).
6. `tests/harness.qml` (900×620, layer Top, `exclusiveZone: 0`) affichant 1 horloge `host: cc` + 1 `host: background`.
7. `tests/run-all.sh` : qmllint Qt6, POST add/move/style/rm, relecture, bornes, persistance après redémarrage.

**Acceptation v1a** (à prouver par commande, sinon ce n'est pas fait) :
- `QML_IMPORT_PATH=$HOME/.config/cc/widgets timeout 10 quickshell -p cc/widgets/tests/harness.qml` → `Configuration Loaded` ;
- `POST /api/widgets {"op":"move","id":"clock-bg","geo":{"x":1.4}}` → clampé à 0..0.95, `revision` +1, fichier relu ;
- redémarrage du process fond (`systemctl --user restart sasquatch-bg`) → horloge au même endroit ;
- `pkill -9 -f "cava -p"` n'est PAS dans ce périmètre : ne pas y toucher.

### v1b — `media`
- `widgets/MediaWidget.qml` (variantes normal/hero/compact/visualizer), `Music.qml` (poll 1 s + viz 60 ms **seulement** si un cava visible ; arrêt du timer quand la surface est cachée).
- Route `GET /api/music/sources` (liste : players MPRIS détectés, `mpd` si socket OK, `pulse` si streams) +
  `POST /api/music/source {"name": "..."}` : pin en mémoire persisté dans `~/.config/cc/music.json`, `active_source()` le respecte, retour à l'auto si la source disparaît.
- Pochette : `/albumart?url=...` (existant), placeholder dégradé `card`→`accent` si 404. Cava : 28 barres 2 px, gap 2, radius 1, gradient accent→accent2, alpha 0.25 au repos.

### v1c — refonte CC (décision de momo : refonte complète, pas de reprise des 3 pages)

**Règle d'or : si un morceau manque, on le crée — jamais de placeholder, jamais une carte vide.**
Chaque zone du board doit être un widget réel du registre. Un widget absent du catalogue se construit
dans la même tranche, au contrat §2, avec ses variantes.

- `FloatingWindow` conservée (toggle `cc.sh`, `close()`, `suppressQuit`, screenshot/OCR inchangés), contenu remplacé :
  board centré max `1340 × (h-80)`, rayon 18, rail gauche 64 px (Accueil / Widgets / Système / Outils + point d'état),
  header (salutation, `clock` en hero, `weather` compact).
- `pages/HomePage.qml` = board 12 colonnes de widgets `host: cc` (défaut livré : media hero 8×2, clock normal 4×2,
  weather normal 4×1, resources normal 4×2, tasks normal 4×2, toggles normal 4×1) — si un de ces widgets n'existe
  pas encore, il est **créé** (v1b/v1d peuvent être fusionnés ici si nécessaire).
- `pages/StudioPage.qml` = **l'espace widget** demandé :
  - colonne gauche : catalogue des widgets du registre, filtré par hôte (`cc` / `background`), vignette + nom + variantes ;
  - centre : aperçu 16:9 du wallpaper (image réelle via `/api/wallpaper*`), widgets posés dessus ; clic = sélection,
    drag = déplacement, poignée = resize, double-clic = retirer ; bouton « + » par entrée du catalogue = ajouter ;
  - droite : panneau de style de la sélection (variante, alpha, blur, radius, accent, options du widget) + « Réinitialiser » ;
  - tout passe par `POST /api/widgets` (jamais d'écriture directe), et l'UI affiche la valeur **relue**.
- `pages/SystemPage.qml` / `pages/ToolsPage.qml` : **copier-coller** des blocs de `main.qml` (perf, outils, screenshot/OCR,
  translate) — aucune réécriture de logique, aucun changement de comportement, mêmes routes.


### v1d — les 13 widgets restants, dans l'ordre du tableau, puis branchement `bar` (`compact`) et `subpage`.

## 8. Vérifications (exactes)

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml <fichier.qml>        # Qt6, pas /usr/bin/qmllint (Qt5, muet)
QML_IMPORT_PATH=$HOME/.config/cc/widgets timeout 10 quickshell -p cc/widgets/tests/harness.qml   # "Configuration Loaded"
curl -s localhost:8765/api/widgets | python3 -m json.tool
bash -n cc/background/background.sh
bash cc/widgets/tests/run-all.sh          # depuis /tmp, pas depuis le dossier du harnais
```
Interdit de conclure sur `qmllint` seul : un fichier qui passe le linter peut tuer le shell au chargement.
Toute affirmation « ça marche » doit venir avec sa commande et sa sortie.

## 9. Interdits (le non-respect invalide la livraison)

1. **Ne jamais lancer le CC plein écran** (`cc/cc.sh`, `quickshell -p main.qml`) : il couvre l'écran et avale les clics de momo. Le harnais 900×620 sert à ça.
2. Ne pas toucher aux keybinds Hyprland, ni à `theme-apply.py`, ni à `apply-wallpaper.sh`, ni au wallpaper.
3. Ne pas committer les 11 fichiers modifiés de momo (`git status --short` les liste). Stage uniquement les chemins nouveaux du brief, nommément, et affiche `git status --short` après.
4. `pkill` toujours crocheté (`[q]uickshell`), et dans un appel séparé du lancement.
5. Commentaires QML en `//` uniquement. Aucun `#`.
6. Aucun `pip install` / `pacman` sans le dire dans le rapport.
7. Aucune couleur en dur, aucun hex hors commentaire de secours.

## 10. Ce qui restera à prouver par momo (pas par rin)

- Le fond d'écran réel en layer `Background` (invisible sous les fenêtres dans le harnais) : lancer
  `~/.config/cc/background/background.sh`, vérifier `hyprctl layers | grep -i background`, capturer, puis fermer.
- La refonte du CC à l'écran (lancement par momo), et la non-régression des outils (screenshot, OCR, translate).
