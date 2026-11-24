# BRIEF — Barre verticale Quickshell (remplace waybar) — v1

Destinataire : rin. Machine : poste de momo. Date : 2026-10-31.
Référence visuelle : `cc/bar/reference/barre-ref.png` (53 × 1072 px, capture réelle de la barre à reproduire fonctionnellement).

---

## 1. Mission

Remplacer **waybar** par une **barre verticale à gauche, pleine hauteur, ~56 px**, écrite en **Quickshell 0.3.2**, qui :
- suit la **palette générée par le wallpaper** (aucune couleur en dur),
- est **paramétrable depuis un fichier JSON des dotfiles** (modules, ordre, largeur, marges, apps épinglées),
- se **masque / affiche avec Super+J** (binding actuel de waybar, à récupérer),
- consomme le **backend du Sasquatch Control Center déjà en place** au lieu de refaire les mêmes sondes.

Livraison = branche de travail dans le dépôt `/home/momo/Downloads/Sasquatch-Dotfile` (tree réellement lue par la session, `~/.config/cc` y est symlinké). Attendu : ça tourne, capture à l'appui, `install.sh` à jour, tests passés. Pas de démo jetable.

---

## 2. État des lieux vérifié (ne pas re-vérifier à l'aveugle, mais ne pas s'en écarter)

| Élément | Valeur réelle mesurée |
|---|---|
| Compositeur | Hyprland, 1 écran `eDP-1` 1920×1080 scale 1 |
| Quickshell | 0.3.2 (`/usr/bin/quickshell`) |
| `~/.config/cc` | → `/home/momo/Downloads/Sasquatch-Dotfile/cc` (dépôt git) |
| Backend CC | `sasquatch-cc.service` **actif**, `http://127.0.0.1:8765` |
| QML réutilisable | `cc/qml/{Palette,Gauge,Sparkline,Tile,IconButton}.qml` |
| Panneau déjà livré | `cc/sidebar/` (PanelWindow + backend 8778) — **modèle de code à imiter, à ne pas modifier** |
| Thème | `~/.config/scripts/theme-apply.py` injecte la palette entre marqueurs dans `cc/qml/Palette.qml` et `waybar/style.css` — **ne jamais éditer ce script** |
| Waybar actuelle | `waybar.service` (systemd user), barre horizontale 1896×36, toggle Super+J → `~/.config/scripts/waybar-toggle.sh` |
| Lanceur | `rofi` (`/usr/bin/rofi`), aussi wofi présent |
| Notifications | `mako` + `makoctl mode do-not-disturb` disponible |
| Polices | 96 entrées Nerd Font installées |
| Session | une seule, graphique, live (captures possibles) |

---

## 3. Décisions verrouillées par momo

1. **Contenu** : tout ce que montre l'image — recherche, workspaces en points, débit réseau ↑/↓, horloge empilée + calendrier, slider volume vertical, apps épinglées **et** apps en cours avec badge, toggles rapides (son · réseau · DND), engrenage réglages.
2. **Comportement** : **toujours visible, réserve l'espace (dock)** ; **Super+J** masque/affiche la barre.
3. **Couleurs** : **palette générée depuis le wallpaper** (cohérente avec `cc`), remise à plat de l'accent. Pas de rouge fixe.
4. **Interactions** : à l'appréciation de l'implémentation, mais la barre doit rester **autonome** — elle ne doit pas dépendre d'une fenêtre du CC pour fonctionner.
5. **Réglages dans les dotfiles** : les options de la barre se pilotent depuis un JSON versionné.
6. **Après rin** : momo valide la capture, puis un tour de polish.

---

## 4. Arbitrages sur l'avis ChatGPT (appliqués / refusés, avec raison)

| Point | Verdict |
|---|---|
| Un `PanelWindow` pour la barre, des `FloatingWindow`/`PopupWindow` séparées pour les popups (jamais une surface qui grandit) | **Adopté** — cohérent avec l'architecture du `cc/sidebar` et avec les pièges Quickshell connus |
| Un `popupController` central (un seul popup ouvert à la fois) | **Adopté** |
| Workspaces via `Quickshell.Hyprland`, pas de parsing `hyprctl` en boucle | **Adopté** |
| Volume : **une seule source de vérité** | **Adopté** → le backend CC (`/api/system/volume`) |
| `Quickshell.Services.Networking` / `Bluetooth` comme source native | **Refusé, avec la vraie raison (vérifié)** : les modules existent bien, mais **pas** sous `Quickshell.Services.*` — ce sont `Quickshell.Networking` et `Quickshell.Bluetooth` (présents dans `/usr/lib/qt6/qml/Quickshell/`). En revanche `Quickshell.Networking` binde **NetworkManager**, et **NM est inactif** sur ce poste (`systemctl is-active NetworkManager` → inactive) : le Wi-Fi est géré par **iwd + systemd-networkd** (`wlan0` 192.168.1.44). ⇒ débit réseau = `/api/stats` (déjà calculé depuis `/proc/net/dev`), état/SSID via `iwctl`/backend |
| Propriétés de fenêtre Hyprland | **Corrigé** : `HyprlandToplevel` n'a **pas** de `class`/`title` direct. On lit `lastIpcObject.class`, `lastIpcObject.title`, `lastIpcObject.address`, `lastIpcObject.workspace.*`, et `wayland` pour la surface. Ne pas inventer `toplevel.class` |
| MPRIS / UPower / Notifications / SystemTray natifs | **Adopté** — modules réellement présents |
| Schéma JSON séparant `bar` / `modules` / `apps` / `clock` / `popups` / `appearance` | **Adopté**, avec le fichier placé **dans le dépôt** : `cc/bar/bar.json` |
| Hot reload : lecture fichier + surveillance, **validation, conservation de la dernière config valide** en cas de JSON cassé | **Adopté** (`Quickshell.Io.FileView` + `watchChanges`) |
| `/api/config` exposé par le backend Python | **Refusé** — un fichier local + `FileView` suffit, pas de nouvel endpoint à maintenir |
| Index des `.desktop` généré côté backend puis exposé en JSON | **Adopté, simplifié** : pas de nouveau service ni de port. Un helper `cc/bar/appindex.py` génère l'index au démarrage et sait lancer une app (`Exec` avec substitution `%f/%u` faite côté Python). QML le lit via `Quickshell.Io.Process` |
| Une instance de barre **par écran** | **Reporté** : un seul écran ici. Écrire le code pour qu'il prenne `Quickshell.screens` en compte sans complexité inutile |
| Stylisation : combiner (1) minimalisme translucide + (2) accent latéral 3 px + (3) surfaces en couches | **Adopté** |
| Les 3 erreurs à éviter : barre ≠ 2ᵉ Control Center ; pas de QML couplé directement au backend ; stabilité > sophistication | **Adopté** |
| Arborescence proposée à la racine `cc/` avec `services/*.qml` | **Refusé** : tout va dans `cc/bar/` (nouveau point d'entrée, on ne touche pas `cc/main.qml` ni `cc/sidebar/`) |

---

## 5. Architecture imposée

```
cc/bar/
├── shell.qml              # ShellRoot : PanelWindow de la barre + popups + singletons
├── bar.json               # config versionnée (voir §7)
├── bar.sh                 # toggle Super+J (modèle : cc/sidebar/sidebar.sh)
├── bar.service            # systemd user, Restart=always (%h/.config/... ports)
├── appindex.py            # index .desktop + lancement (--json, --launch <id>)
├── README.md              # options, lancement, dépannage
├── reference/barre-ref.png
├── qml/                   # composants réutilisables du projet (BarPalette.qml, Pill, IconButton, AppIcon, Badge, Section)
├── modules/               # un fichier par module (Search, Workspaces, NetRate, Clock, VolumeSlider, AppDock, QuickToggles, Settings)
├── popups/                # CalendarPopup, VolumePopup, NetworkPopup, NotificationsPopup
└── tests/                 # run-all.sh + qmllint + probes
```

Règles d'architecture :
- **Un singleton `Config.qml`** (lecture + validation `bar.json`, signaux de changement) : aucun module ne lit le JSON directement.
- **Un singleton `Palette.qml` du projet** : il consomme `GET /api/palette` (CC 8765) toutes les 2 s et expose des tokens typés (`bg`, `card`, `text`, `textDim`, `accent`, `good`, `warn`, `hot`). Aucun module ne contient de hex, hors valeurs de secours commentées.
- **Un singleton `Backend.qml`** : un seul point d'entrée HTTP (stats, volume, luminosité, musique) + tous les POST. Un timer unique (~2 s) alimente tout le monde ; **aucun timer par module**.
- Les popups s'ouvrent en `FloatingWindow`/`PopupWindow` ancrées au bord gauche, une seule à la fois.

---

## 6. Sources de données réelles (payloads mesurés le 2026-10-31)

```
GET  http://127.0.0.1:8765/api/palette
     {"bg":"#151515","bgSolid":"#151515","card":"#2d2d2d","cardSolid":"#2d2d2d",
      "text":"#d1d1d1","textDim":"#7c7c7c","accent":"#dddddd","accent2":"#44dddddd",
      "overlay":"#99021933","good":"#a6e3a1","warn":"#f9e2af","hot":"#f38ba8"}

GET  /api/stats
     {"ts":..., "cpu":28.0, "cores":[...], "load":[...],
      "ram":{"used":9986,"total":15863,"pct":63.0},
      "gpu":{"util":0.0,"vram_used":9.0,"vram_total":6144.0,"temp":46.0},
      "cpu_temp":63.0,"gpu_temp":46.0,
      "net":{"up":139.6,"down":417.7,"iface":"wlan0"},   # débit déjà calculé
      "uptime":228788,"refresh":6}

GET  /api/system/volume        -> {"volume":41,"muted":false}      (PLAT, pas imbriqué)
POST /api/system/volume        (body {"volume": 0-100} ou {"delta": ±N} selon le code existant)
GET  /api/system/brightness     POST idem
GET  /api/music/status          -> {"source":"none","playing":false,"title":null,...}
POST /api/music/toggle|next|prev|seek|stop
```

**Attention** : `accent` vaut `#dddddd` en ce moment (wallpaper noir et blanc) — l'accent est donc quasi blanc. La barre doit **relever l'accent vers la couleur de texte** quand il est trop proche du fond (voir §8), sinon les états actifs sont invisibles. C'est un cas déjà rencontré sur ce poste.

Pas de source native fiable pour le réseau : `Quickshell.Networking` existe mais binde NetworkManager, **inactif** ici (Wi-Fi = iwd + systemd-networkd) → réseau via `/api/stats`. Batterie → `Quickshell.Services.UPower` (présent). Le débit est en **Ko/s** (le formater en Ko/Mo).

---

## 7. `cc/bar/bar.json` — schéma et rechargement

```json
{
  "bar": { "enabled": true, "position": "left", "width": 56,
           "marginTop": 8, "marginBottom": 8, "marginLeft": 6,
           "exclusiveZone": true, "radius": 18, "spacing": 12, "blur": true },
  "modules": ["search", "workspaces", "netRate", "clock", "volume",
              "pinnedApps", "runningApps", "quickToggles", "settings"],
  "clock": { "hourFormat": "HH", "minuteFormat": "mm", "period": "AP", "calendarIcon": true },
  "apps": [
    {"id":"spotify","desktop":"spotify.desktop","class":"Spotify","enabled":true},
    {"id":"discord","desktop":"discord.desktop","class":"discord","enabled":true},
    {"id":"terminal","desktop":"kitty.desktop","class":"kitty","enabled":true},
    {"id":"vlc","desktop":"vlc.desktop","class":"vlc","enabled":true}
  ],
  "popups": { "calendar": true, "volume": true, "network": true, "notifications": true },
  "appearance": { "panelAlpha": 0.75, "cardAlpha": 0.55, "iconSize": 20, "hoverOpacity": 1.0 }
}
```

Contraintes :
- `modules` est **une liste ordonnée** : ajouter/retirer un module ne doit demander aucune modification de code.
- `width` + marges : `exclusiveZone` doit réserver **largeur + marges latérales**, pas seulement la largeur (piège classique : fenêtres maximisées qui passent sous la barre).
- Rechargement à chaud : `FileView` + `watchChanges`; **JSON invalide ⇒ on garde la dernière config valide** et on logge, on ne casse jamais la barre.
- Chaque clé absente prend un défaut **dans le code**, pas dans le JSON (le JSON livré reste lisible et minimal).

---

## 8. Spécification module par module (ordre de haut en bas)

| # | Module | Donnée | Comportement / interaction | Détails |
|---|---|---|---|---|
| 1 | **Search** | — | clic → lance `rofi -show drun` (chemin résolu, pas de shell nu) | icône loupe Nerd Font, pilule circulaire |
| 2 | **Workspaces** | `Quickshell.Hyprland.workspaces` + événements | clic → `dispatch workspace N` ; molette → précédent/suivant | points verticaux, l'actif s'allonge en pilule de 3 px de large et 22 px de haut ; l'occupé est plus opaque ; tooltip = fenêtres du workspace |
| 3 | **NetRate** | `/api/stats` → `net.up/down` | clic → popup réseau (iface, IP, débit, graph sparkline) | format `↑ 660 B/s`, `↓ 1,2 Mo/s` ; texte 10-11 px, deux lignes alignées à droite |
| 4 | **Clock** | `Qt.formatDateTime` locale | clic → `CalendarPopup` | trois lignes `HH` / `mm` / `AM-PM`, chiffres tabulaires, + icône calendrier discrète ; tooltip = date longue en japonais/romaji |
| 5 | **Volume** | `/api/system/volume` (+ POST) | molette → ±5 % ; clic → `VolumePopup` (sortie, mute, luminosité) | **slider vertical en pointillés** : 12 tirets, remplis jusqu'au niveau ; icône mute quand muet |
| 6 | **PinnedApps** | `bar.json.apps` + `appindex.py` | clic → lance via `appindex.py --launch <id>` ; clic si déjà ouvert → focus | badge = **nombre de fenêtres** de cette classe (pas de processus) ; point d'accent si ouvert ; l'app ouverte n'est pas répétée dans le cluster 7 |
| 7 | **RunningApps** | `Quickshell.Hyprland.toplevels` groupés par classe normalisée | clic → focus ; clic droit → menu des fenêtres | icône résolue via l'index desktop ; maximum visible puis indicateur de débordement (pas de scroll caché) |
| 8 | **QuickToggles** | backend + commandes système | son (mute) · réseau (état + clic popup) · DND (`makoctl mode -t do-not-disturb`) | pilule unique contenant 3 icônes ; état actif = fond accent α 0.3 |
| 9 | **Settings** | — | clic → ouvre le CC existant (`hyprctl dispatch exec ~/.config/cc/cc.sh`) | engrenage, dernier élément, séparé par un espace plus grand |

Chaque module doit avoir : état normal, survol, actif, **et un état d'erreur visible** (donnée absente ⇒ icône + tooltip « indisponible », jamais un blanc ni un crash).

---

## 9. Style (palette générée, verre léger, accent latéral)

- **Fond de barre** : `alpha(palette.bg, 0.75)`, `border: 1px alpha(palette.card, 0.35)`, `radius 18`.
- **Blocs/pilules** : `alpha(palette.card, 0.55)` ; survol `+0.10` ; actif `alpha(accent, 0.30)`.
- **Accent latéral** : barre de 3 px, arrondie, à gauche du module actif (workspace actif, app focalisée) — seule touche colorée avec les états.
- **Hiérarchie** : `text` pour les valeurs, `textDim` pour les labels secondaires (unité, AM/PM).
- **Formes** : pilules pleines, pas de séparateurs dessinés — l'espace fait la séparation (12 px entre blocs, 20 px avant/après les clusters).
- **Animations** : 120–180 ms `Easing.OutCubic` sur hauteur/opacité uniquement. **Rien qui tourne au repos.**
- **Blur** : `BackgroundEffect` (`ext-background-effect-v1`), radius 12–20, 2–3 passes, fenêtre en `color: "transparent"`. Repli propre si le compositeur ne suit pas : surface à alpha plus élevé.
- **Accent trop clair/sombre** : si `luminance(accent)` est à moins de 15 % de celle de `bg`, tirer l'accent vers `text` (le cas se produit avec un wallpaper monochrome — c'est l'état actuel).
- **Tailles** : icônes 20 px dans un conteneur cliquable de 40–44 px ; polices 10/11/13 px, `JetBrainsMono Nerd Font` (déjà installée).
- **Contraste** : lisible sur wallpaper clair comme sombre.

---

## 10. Règles techniques — les pièges déjà payés sur ce poste

1. **Aucune couleur en dur** hors valeurs de secours commentées. Le reste vient de `/api/palette`.
2. **Ne jamais animer `exclusiveZone` avec la largeur** (désynchronisation). Zone réservée constante ; on anime l'offset/opacité interne. Masquage = `exclusiveZone: 0` + largeur de fenêtre nulle **sans animation**, ou déplacement hors écran.
3. **`PanelWindow` n'apparaît pas dans `hyprctl clients`** — c'est une layer surface. Vérifier avec `hyprctl layers` et matcher `namespace`/`pid`, jamais un `grep -c`.
4. **`pkill -f` se tue lui-même** : motif crocheté (`[q]uickshell.*bar/shell.qml`) et dans un appel séparé du lancement.
5. **Le toggle est un toggle** : un deuxième lancement ferme la barre. Tester une seule fois puis sonder sans relancer.
6. **QML : uniquement des commentaires `//`** — un `#` casse le parse. `qmllint` après chaque édition.
7. **Ne pas toucher** : `cc/main.qml`, `cc/sidebar/`, `cc/server.py`, `~/.config/scripts/theme-apply.py`, `waybar/` (sauf mention §11).
8. **Le blur dépend du compositeur** : `decoration:blur:enabled` peut être à 0 → vérifier avant de conclure que `BackgroundEffect` ne marche pas.
9. **Une image ne doit jamais déterminer la largeur** : `width/height` fixes + `fillMode: PreserveAspectCrop` (album art, icônes d'app).
10. **Pas de timer par module** : un seul timer dans `Backend.qml`.
11. **Migration de données** : les routes CC sont GET ou POST — lire `server.py` avant d'appeler (un GET sur une route POST rend un 404 trompeur).
12. **Écrire les scripts en `bash -n`** et les tester avant de dire « ça marche ».

---

## 11. Intégration aux dotfiles (obligatoire, sinon non livré)

1. **`cc/bar/bar.sh`** : toggle (détection par processus, message clair sans session Wayland, attente du backend CC, `quickshell -p <abs>/shell.qml` en avant-plan).
2. **`cc/bar/bar.service`** : unité systemd user, `Restart=on-failure`, chemins `%h/.config/cc/bar/...` (portable).
3. **`hypr/keybinds.conf`** : `bind = $mod, J, exec, ~/.config/cc/bar/bar.sh` — remplacer la ligne `waybar-toggle.sh` (commenter l'ancienne avec la date).
4. **`install.sh`** :
   - `link "$DOTDIR/cc/bar" "$CONFIG/cc/bar"` est déjà couvert si tout `cc` est lié — **vérifier**, sinon ajouter,
   - lier `bar.service` dans `$SD_USER` + l'activer,
   - ajouter les dépendances manquantes avec un commentaire d'usage (`rofi` déjà là ; vérifier `playerctl`, `brightnessctl`, `python` side).
5. **Waybar** : **ne pas la désactiver** dans cette phase. Elle reste en place pendant le développement (on la coupe le temps d'une capture). Le basculement (`systemctl --user disable --now waybar`, retrait du binding, mention dans le README) se fait **en fin de mission**, une fois la capture validée, et documenté dans le README.
6. **README.md** : contenu recap, chaque clé de `bar.json`, comment ajouter une app épinglée, comment changer la largeur, dépannage (barre absente = quoi regarder), et l'état « waybar débranchée / réactivable en une commande ».

---

## 12. Vérifications à produire dans le rapport (preuves, pas d'avis)

1. `qmllint` sur **chaque** fichier QML créé, sortie collée (un exit ≠ 0 doit être comparé à la version de base avant d'être présenté comme une régression).
2. `bash -n` sur `bar.sh`, `install.sh` modifié.
3. Lancement réel une seule fois + `hyprctl layers | grep -A1 -i quickshell` montrant `xywh` de la barre.
4. Capture `grim -g "<x> <y> <w> <h>"` de la barre **et** une capture plein écran ; décrire ce qu'on voit sur les pixels.
5. Croisement de 3 valeurs affichées avec l'API (`volume`, `net.up`, `ram.pct`) — un chiffre à l'écran qui ne correspond pas = bug de binding.
6. Test du toggle Super+J (deux appels, la barre revient et `exclusiveZone` aussi).
7. Test du rechargement de `bar.json` (changer `width`, la barre suit sans relancer ; mettre un JSON cassé, la barre survit).
8. `systemctl --user status` de `bar.service` si le mode service est retenu.

---

## 13. Interdits

- Copier-coller du CSS de waybar : la barre est en QML.
- Réécrire la logique système (CPU, GPU, RAM, volume, luminosité, musique) dans QML ou dans un second backend.
- Toucher `cc/sidebar/`, `cc/main.qml`, `cc/server.py`, `theme-apply.py`, `~/.config/hypr/conf.d/*` hors la ligne de keybind.
- Inventer des modules non demandés (météo, IA, visionneuse) ou une seconde barre horizontale.
- Livrer sans capture : « ça fonctionne » sans pixel ni `xywh` n'est pas une preuve.

---

## 14. Rapport attendu à la fin

- Liste des fichiers créés/modifiés + `git status --short` (staging explicite, ne pas emporter les modifications non liées du dépôt).
- Les sorties des vérifications du §12 (commandes + résultats bruts).
- 3 points ouverts / risques, honnêtement.
- La commande exacte pour désactiver waybar et celle pour revenir en arrière.
