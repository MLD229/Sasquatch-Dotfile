# Rapport rin — tranche « polish widgets » (§1, §2, §5.1 et §5.3)

Date : 2026-11-01 13:30 CET · Repo : `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`)
Verdict : **§1 + §2 (14 widgets) + §5.1 + §5.3 livrés et vérifiés. 155 contrôles OK / 0 FAIL.**
Hors tranche (consigne) : `pages/SystemPage.qml` et `pages/ToolsPage.qml` — **non touchés**.

## §0 — Porte d'entrée (rétablie par momo)

| # | Contrôle | Action | Preuve (sortie réelle) |
|---|---|---|---|
| 0.1 | `curl -s -o /dev/null -w '%{http_code}' localhost:8765/api/widgets` | aucune modification | `200` |
| 0.2 | idem `/api/notes` | idem | `200` |
| 0.3 | État du service | `systemctl --user is-active sasquatch-cc` | `active` |
| 0.4 | Board réel | `curl -s localhost:8765/api/widgets` | `revision 76`, **9 instances** |
| 0.5 | Le harnais charge | `timeout 25 quickshell -p cc/widgets/tests/harness.qml` | `harness: rendu écrit = true` |

## §1 — Règle de lisibilité

| Contrôle | Action | Preuve |
|---|---|---|
| Chaque widget a un état explicite (chargement → `—` → valeur) | Ajout de compteurs de sondes dans `Env.qml` (`weatherPolls`, `statsPolls`, `tasksPolls`, `soundPolls`, `batteryPolls`) : 0 sonde revenue = `chargement…`, sonde revenue vide = `indisponible`, sinon valeur. Appliqué aux 14 widgets. | `grep -n "Polls" cc/widgets/Sasquatch/Widgets/Env.qml` → 5 propriétés ; Polish : `OK tâches · état vide : « Aucune tâche » affiché` |
| Aucun jargon à l'écran (`MPRIS`, `open-meteo`, `wpctl`, `pipewire`, `makoctl`, chemin) | Vocabulaire réécrit : `MPRIS`→nom du lecteur, `Pulse`→`Audio système`, `open-meteo`→`actualisé il y a N min`, `CPU/RAM/GPU`→`Processeur/Mémoire/Carte graphique`, `mako absent`→`Notifications indisponibles · sudo pacman -S mako`, `Hyprland muet`→`Bureaux indisponibles` | Contrôle automatique dans `polish.sh` (`VOCAB_KO="MPRIS\|Pulse\|open-meteo\|wpctl\|pipewire\|makoctl\|Hyprland\|/home/"`) : 14 × `OK … aucun jargon technique visible` |
| Outil manquant = nom + commande | `Gestion du réseau indisponible`, `Wi-Fi · NetworkManager non installé` + `sudo pacman -S networkmanager`, `Notifications indisponibles · sudo pacman -S mako`, `Indisponible · sudo pacman -S …` | `OK connexions · audio réel : « Son · Audio interne Stéréo analogique » affiché` + `sudo pacman -S networkmanager` présent au rendu (`/tmp/polish-final/connectivity-normal.png`) |

## §2 — Audit widget par widget (14)

Chaque ligne : **contrôle → action → preuve**. Les preuves sont des lignes réelles de
`bash cc/widgets/tests/polish.sh` (sortie du 2026-11-01 13:27), qui compare le texte
**affiché** à la réponse **HTTP** de la route.

| # | Widget | Contrôle | Action | Preuve |
|---|---|---|---|---|
| 1 | media | La pilule de source nomme le lecteur ; pas de `0:00 / 0:00` ; pochette absente = glyphe | `Music.qml` : `readerLabel()` (mpris→`Brave`-like, mpd→`MPD`, pulse→`Audio système`, web→`Navigateur`), `prettyName()`, `stateLabel()` ; menu de sources = `sourceChoices` (noms humains + état, `Automatique` en tête) ; temps masqué si `duration <= 0` | `OK média : « audio stream #5 » affiché` · `OK média · lecteur nommé : « Audio système » affiché` · `OK média · pilule de source : « ● Audio système » affiché` · `OK média · pas de « 0:00 / 0:00 »` |
| 2 | weather | Pied sans `open-meteo`, âge en minutes ; `°` à la taille du chiffre ; normal réparti | `ageText` (`actualisé il y a N min`), `degSize = 0.95 × taille`, nouvelle disposition normal (titre `Météo` en haut / température au centre / sous-titre `Lyon · plutôt dégagé` en bas) | `OK météo · sous-titre ville · ciel : « Lyon · plutôt dégagé » affiché` · `OK météo hero · fraîcheur en français : « actualisé à l'instant » affiché` · rendu `weather-normal.png` |
| 3 | resources | `GPU 0 %` ambigu → `—` si non mesuré ; anneaux alignés ; sparkline nue | `cpuMeasured/ramMeasured/gpuMeasured` (l'absence de champ n'est pas un zéro), anneau vide + `—` si non mesuré, `Mesure…`/`Mesure indisponible`, légendes `Processeur · Mémoire · Carte graphique`, aire dégradée de la sparkline supprimée, police de légende ajustée à la colonne | `OK ressources · processeur et mémoire : valeurs affichées cohérentes avec /api/stats (21,24,24,38,38,38)` · `OK ressources · légende : « Carte graphique » affiché` |
| 4 | tasks | Champ d'ajout explicite + `+` ; état vide sans doublon ; compteur lisible | Colonne `Mes tâches`, compteur `N restantes`/`tout est fait`/`—`, état vide `Aucune tâche`, champ `Ajouter une tâche…` + bouton `+` (POST identique) | `OK tâches · champ d'ajout explicite : « Ajouter une tâche… » affiché` · `OK tâches · bouton + : « + » affiché` · `OK tâches · état vide : « Aucune tâche » affiché` |
| 5 | volume | Glyphes cohérents, muet visible (icône barrée + valeur grisée), libellés exacts | `Volume`→`Son`, `Lumière`→`Luminosité`, valeurs `51 %` / `95 %`, `Son coupé`, `—` si non mesuré, pilule `Réglage du son indisponible` (non cliquable) | `OK son · valeur servie : « 51 % » affiché` · `OK luminosité · valeur servie : « 95 % » affiché` |
| 6 | battery | Icône pleine au niveau réel ; `100 %` seul | `stateText` : `Full` → chaîne vide (`pleine` supprimé), `En charge`, `Sur batterie`, `Batterie non détectée` | `OK batterie · niveau réel : « 100 % » affiché` · `OK batterie · pas de « pleine » : pas de « pleine »` |
| 7 | playlist | UN seul message vide ; titre accordé ; piste courante marquée | Titre `Ma musique`, compteur `N morceau(x)`, centre `Liste vide` (pied muet en conséquence), `Liste indisponible` | `OK playlist · un seul message vide : « Liste vide » affiché` |
| 8 | calendar | Aujourd'hui entouré ; tâches datées sur leur jour ; mois vide sans message trompeur | Titre `Calendrier` + sous-titre `novembre 2026` (mois en toutes lettres via `Env.monthLong`), cercle tracé autour du jour, pied unique `Rien de prévu` / `Calendrier indisponible` / `Chargement…` | `OK calendrier · mois en toutes lettres : « novembre 2026 » affiché` · `OK calendrier · jour du jour : « 1 » affiché` · `OK calendrier · rien de prévu : « Rien de prévu » affiché` |
| 9 | connectivity | `NetworkManager requis · aucun` incompréhensible → `Wi-Fi : NetworkManager non installé` + commande ; doublon BT supprimé | Widget réécrit : `Connexions` + 3 lignes `Catégorie · état` (`Wi-Fi · …`, `Bluetooth · Activé`, `Son · Audio interne …`), commande d'install sur une ligne secondaire | `OK connexions · une ligne par info (Bluetooth) : « Bluetooth · Activé » affiché` · `OK connexions · pas de doublon « adaptateur actif »` |
| 10 | toggles | État RÉEL relu ; outil absent grisé + raison + commande ; libellés courts non tronqués | Titre `Modes rapides`, libellés `Ne pas déranger / Flou / Mode nuit / Mode léger`, compact `Silence / Flou / Nuit / Léger` (plus de `DND`), `Activation…`, `Indisponible · raison + commande` | `OK modes · état relu = état servi ({"dnd":false,"blur":false,"bluesun":false,"lite":true})` · `OK modes · ancien libellé banni : pas de « Lumière chaude »` |
| 11 | notifications | Nom de fichier → `Capture d'écran 20:28` ; corps ≤ 2 lignes ; compteur | Helpers déplacés dans `Notifs.qml` (`noteTime`, `isTechnical`, `humanTitle`, `humanBody`) + `5 nouvelles` en sous-titre (badge dédoublonné), corps 2 lignes `ElideRight` | `OK notifications · compteur : « 5 nouvelles » affiché` · `OK notifications : aucun nom de fichier à l'écran` · `OK titre d'une capture horodatée` (cas réel : `20261031_202801_…png` → `Capture d'écran 20:28`) |
| 12 | workspaces | Compteur lisible, bureau actif évident | `N fenêtres` / `Aucune fenêtre` / `Bureaux indisponibles` (plus de `Hyprland muet`), actif : remplissage accent + contour 2 px | `OK bureaux · compteur : « 14 fenêtres » affiché` (valeur = `hyprctl -j workspaces`) |
| 13 | apps | Icône introuvable = pastille + nom propre + `Retirer` | `Apps.displayName()` (`explorer.exe` → `Explorer`), tuile « introuvable » avec nom + action `Retirer`, `Apps.removeFavorite()` (écriture atomique de `bar.json`, jamais de retrait muet) | `OK favoris · app introuvable nommée proprement : « Explorer » affiché` · `OK favoris · action Retirer : « Retirer » affiché` |
| 14 | notes | Ajout / suppression / persistance après redémarrage | `Mes notes`, `N note(s)`, `Aucune note`, `Notes indisponibles`, champ `Ajouter une note…` + `+` | `OK POST /api/notes add → relu par GET (count=1)` · `OK notes · la note survit au redémarrage du backend` · `OK POST /api/notes rm → note retirée (id 1)` |

## §4 / §5.1 + §5.3 — livrables

| Contrôle | Action | Preuve |
|---|---|---|
| `cc/widgets/tests/polish.sh` : un test par widget (curl de la route + rendu + valeur affichée ∈ réponse) | Écrit : 16 sections, harnais d'un seul widget (`polish-harness.qml`), rendu PNG par widget, comparaison texte affiché ↔ HTTP | `SASQUATCH_POLISH_OUT=/tmp/polish-final bash cc/widgets/tests/polish.sh` → **`== bilan : 155 OK / 0 FAIL ==`**, 18 PNG produits |
| Harnais jamais en plein écran (brief §9) | `polish-harness.qml` : `PanelWindow` layer Top, taille = variante + marge, `Qt.quit()` après relevé | `cc/widgets/tests/polish-harness.qml` (nouveau) ; aucun `cc/main.qml` ouvert |
| Règles de copy non visibles à l'écran (titre de capture) | `copy-tests.qml` | `OK titre d'une capture horodatée` → `Capture d'écran 20:28`, `COPY-DONE 0` |
| État relu = état servi (interrupteurs) | `state-tests.qml` | `OK modes · état relu = état servi ({"dnd":false,"blur":false,"bluesun":false,"lite":true})` |
| Rien de cassé ailleurs | `bash cc/widgets/tests/run-all.sh` | `== bilan : 69 OK / 0 FAIL ==` (qmllint Qt6, chargement, API widgets.json, persistance, média/épingle) |
| qmllint Qt6 sur tout le module + tests | inclus dans polish.sh §1 | 41 × `OK <fichier>.qml` (aucune `Error:`) |

Rendus : `/tmp/polish-final/*.png` (18 vues, une par widget/variante) ; vue d'ensemble du board
recapturée : `docs/rin-polish-board.png`.

## Ce qui reste

1. **Clic sur un bureau (`workspaces`)** : `Hyprland.dispatch("workspace N")` inchangé, mais un clic
   réel déplace le focus — non testé à la souris (le compteur, lui, est vérifié contre `hyprctl`).
   À valider par momo.
2. **`SystemPage` / `ToolsPage`** : hors tranche (consigne explicite), non touchés.
3. **Menu de choix du lecteur (media)** : rendu en surimpression, non capturé par le harnais
   (il faut un clic). Labels humains vérifiés par le code et par la pilule.
4. **Défauts visuels restants** : la carte `media` `normal` garde un cava mince quand aucun
   morceau ne joue (ligne de base 1 px, volontaire) ; l'aspect final (alphas, halo) reste à
   l'appréciation de momo à l'écran.

## Contrôles que SEUL momo peut valider à l'écran

- Le board complet à 1920×1080 : espacement réel, halo du verre, tailles perçues.
- Le menu de sources du widget média (clic sur la pilule) : noms `Brave` / `MPD` / `Audio système`.
- Un clic sur une pastille de bureau, et le double-clic en édition (Studio).
- Sur une session où NetworkManager est installé : `Wi-Fi · <ssid>` (ici la machine est sous iwd,
  donc la carte affiche la commande d'installation).

## `git status --short`

Seuls ces fichiers portent mes modifications (les autres `M`/`A` sont le travail antérieur de momo) :

```
AM cc/widgets/Sasquatch/Widgets/Apps.qml
AM cc/widgets/Sasquatch/Widgets/Env.qml
AM cc/widgets/Sasquatch/Widgets/Music.qml
AM cc/widgets/Sasquatch/Widgets/Notifs.qml
AM cc/widgets/Sasquatch/Widgets/widgets/AppsWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/BatteryWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/CalendarWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/ConnectivityWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/MediaWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/NotesWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/NotificationsWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/PlaylistWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/ResourcesWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/TasksWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/TogglesWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/VolumeWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/WeatherWidget.qml
AM cc/widgets/Sasquatch/Widgets/widgets/WorkspacesWidget.qml
?? cc/widgets/tests/polish.sh
?? cc/widgets/tests/polish-harness.qml
?? cc/widgets/tests/copy-tests.qml
?? cc/widgets/tests/state-tests.qml
?? docs/RAPPORT-rin-widgets-polish.md
?? docs/rin-polish-board.png
```

`git diff --stat -- cc/widgets` : `21 files changed, 949 insertions(+), 451 deletions(-)`.
Aucun fichier de momo non commité n'a été modifié hors de ce périmètre (`cc/main.qml`,
keybinds, `pages/SystemPage.qml`, `pages/ToolsPage.qml` : intacts).
