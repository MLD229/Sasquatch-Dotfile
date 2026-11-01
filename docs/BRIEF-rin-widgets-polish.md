# BRIEF rin — Peaufinement : widgets qui « ne marchent pas », pages Système/Outils, style

Destinataire : rin. Repo live `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`). Quickshell 0.3.2.
Brief précédent (architecture, contrat §2, style §3, interdits §9) : `docs/BRIEF-rin-widgets-v1.md` — toujours valable.

Commande de momo : « plusieurs utils marchent pas ou incompréhensibles, la partie Outils n'a pas été
retouchée, à faire, peaufiner et styliser ».

## 0. AVANT tout diagnostic de widget : vérifier le backend

Le port 8765 a été tenu par un backend étranger (`/home/work/.config/cc/server.py`, compte `work`), qui
ne connaît pas les routes récentes → **des widgets « morts » n'étaient qu'un backend périmé**. À chaque
session :

```bash
curl -s -o /dev/null -w "%{http_code} /api/widgets\n" localhost:8765/api/widgets
curl -s -o /dev/null -w "%{http_code} /api/notes\n"   localhost:8765/api/notes
```

Si l'un des deux n'est pas `200`, **ne touche à aucun widget** : le problème est le port, pas le QML.
Écris-le dans le rapport au lieu de « corriger » des fichiers sains.

## 1. Règle de lisibilité — un widget muet est un bug

Chaque widget doit afficher un état explicite, jamais un 0 ou un blanc :
`chargement…` → `—` (donnée absente) → valeur. Et un état « indisponible » nomme l'outil manquant **et**
la commande d'install (`sudo pacman -S …`), comme déjà fait pour hyprsunset.

**Aucun jargon technique visible par l'utilisateur** : pas de `MPRIS`, `open-meteo`, `wpctl`, `pipewire`,
`makoctl`, pas de chemin de fichier. Vocabulaire : « Brave », « lecteur MPD », « audio interne »,
« il y a 4 min », « capture d'écran 20:28 ».

## 2. Audit widget par widget (constats sur rendu réel — corriger chacun, avec preuve)

| # | Widget | À corriger |
|---|---|---|
| 1 | media | pillule de source affiche `MPRIS` → libellé humain (nom du lecteur, `MPD`, `Audio système`) + menu de choix lisible ; `0:00 / 0:00` quand rien ne joue → masquer le temps ; pochette absente = pastille dégradée avec glyphe note, pas un carré vide |
| 2 | weather | pied `données open-meteo · il y a 280 s` → `actualisé il y a 5 min` ou rien ; `°` à la taille du chiffre ; variante normal : contenu réparti (plus de vide en bas) |
| 3 | resources | `GPU 0 %` ambigu → `GPU —` si non mesuré ; anneaux alignés à la même taille ; sparkline sans fioritures |
| 4 | tasks | champ d'ajout explicite (placeholder + bouton `+`) ; état vide `aucune tâche` sans doublon |
| 5 | volume | glyphes cohérents (volume / luminosité), état muet visible (icône barrée + valeur grisée) |
| 6 | battery | vérifier que l'icône se remplit vraiment au niveau réel (à 100 % elle doit être pleine) ; `pleine` redondant avec `100 %` → garder un seul |
| 7 | playlist | un seul message vide ; chaque piste : titre tronqué à la fin, durée, piste courante marquée |
| 8 | calendar | aujourd'hui réellement entouré ; tâches datées placées sur leur jour ; mois vide = pas de message trompeur |
| 9 | connectivity | `NetworkManager requis · aucun` incompréhensible → `Wi-Fi : NetworkManager non installé` + commande ; `BT actif · adaptateur actif` = doublon → une seule ligne d'état |
| 10 | toggles | chaque interrupteur affiche l'état RÉEL relu ; outil absent = grisé + raison + commande ; libellés courts non tronqués |
| 11 | notifications | nom de fichier d'une capture illisible (`notify-send-2026…`) → titre humain `Capture d'écran 20:28` ; corps sur 2 lignes max, ellipse propre |
| 12 | workspaces | compteur de fenêtres lisible, bureau actif évident, clic vérifié (dispatch) |
| 13 | apps | icône introuvable = pastille avec initiale + nom propre (`explorer.exe` → `Explorer`) |
| 14 | notes | ajout / suppression / persistance après `systemctl --user restart sasquatch-cc` |

## 3. Pages Système et Outils — non retouchées, à faire

Elles datent de l'ancien `main.qml` : **mêmes tokens de verre, mêmes rayons, même typo que le board**.

- `pages/SystemPage.qml` : passer les blocs perf au style carte (`Theme.fill`, halo, `radiusCard`),
  aérer, un titre par bloc, plus aucun `Rectangle` gris à bord dur.
- `pages/ToolsPage.qml` : **c'est la partie que momo dit incompréhensible.** Même travail de style, plus :
  - un titre + une ligne d'explication par outil (à quoi ça sert, en français simple) ;
  - un bouton principal unique et nommé (`Capturer une zone`, `Lire un texte à l'écran`, `Traduire`) ;
  - chaque bouton dit ce qui va se passer avant le clic, et affiche le résultat ou l'erreur dans la page ;
  - un outil dont la dépendance manque (grim/slurp/tesseract…) est grisé avec `sudo pacman -S …` ;
  - **aucun changement de logique** : mêmes routes, mêmes fonctions, seul l'habillage et les libellés changent.
- Les widgets du board et ces pages doivent être indiscernables en style : mêmes alphas, même halo,
  même échelle de rayons, même interligne.

## 4. Méthode imposée

Pour chaque point, un tableau `contrôle → action → preuve` (commande + sortie, ou capture). Un
« corrigé » sans preuve est traité comme non fait. Interdits du brief v1 §9 inchangés :
jamais `cc/main.qml` en plein écran, jamais de keybind touché, jamais les fichiers non commités de momo,
`pkill` crocheté, commentaires QML `//`, aucune couleur en dur.

## 5. Livrable de cette tranche

1. les 14 widgets corrigés (état explicite, copy française, style cohérent) ;
2. `SystemPage` + `ToolsPage` restylées et rendues compréhensibles ;
3. `cc/widgets/tests/polish.sh` : un test par widget — `curl` de la route, chargement du harnais,
   capture, et vérification que la valeur affichée existe dans la réponse HTTP ;
4. un rapport court : ce qui a été corrigé, ce qui reste (avec la raison), et la liste des contrôles
   que SEUL momo peut valider à l'écran.
