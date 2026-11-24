# BRIEF v3 — Barre verticale : correctifs + épinglage d'apps (2026-10-31, soir)

**RÈGLE ABSOLUE DE CETTE SESSION : momo travaille sur sa machine. Tu ne lances RIEN.**
Interdits, sans exception :
- pas de `systemctl --user restart/stop/start sasquatch-bar`
- pas de `quickshell -p …`, pas de `bar.sh`, pas de `tests/run-all.sh`, pas de `tests/verify-v2.sh`
- pas de `hyprctl dispatch` (workspace, exec), pas de lancement de rofi, pas de `notify-send`
- pas de `qs ipc call` sur une fonction d'action (elles pilotent le bureau)

Autorisé : lire les fichiers, `qmllint`, `bash -n`, `py_compile`, `git status`, `grep`, calculs.
Toutes les preuves dynamiques sont **différées** : tu livres une checklist que momo exécute lui-même.
Il relancera la barre quand il veut (`systemctl --user restart sasquatch-bar`).

État actuel : barre v2 en service (46 px, alpha 0.24/0.20, entièrement centrée, waybar débranchée).
Lis `cc/bar/README.md` (§10 les corrections d'Asuka, §11 les décisions) avant de coder.

---

## 1. La loupe ouvre le mauvais rofi (bug net)

`cc/bar/modules/Search.qml` lance `["/usr/bin/rofi", "-show", "drun"]` → rofi **sans thème**.
Le lanceur du dotfile est `~/.config/rofi/scripts/launcher.sh` (thème `~/.config/rofi/themes/sasquatch.rasi`,
mode combi `drun,calc`, PATH corrigé pour qalc, une seule instance).

- Clic loupe → `hyprctl dispatch exec ~/.config/rofi/scripts/launcher.sh` (même style d'appel que le
  module Settings v2 : chemin absolu résolu, `Process` + code de sortie journalisé).
- Repli explicite si le script manque : `rofi -show drun -theme ~/.config/rofi/themes/sasquatch.rasi`.
- Si ni l'un ni l'autre : état visible « lanceur introuvable », pas un clic muet.
- L'infobulle devient « Rechercher (Super) » puisque c'est le lanceur complet du dotfile.

## 2. Zones de molette — à reprendre partout

Aujourd'hui seuls `VolumeSlider` et `Workspaces` ont un `onWheel`, et sur Workspaces il est posé
**par point** : rouler entre deux points ne fait rien. Attendu, avec **une zone de molette par module,
couvrant tout le bloc** (pas seulement le glyphe) :

| Module | Molette haut/bas |
|---|---|
| Workspaces | workspace précédent / suivant (`dispatch workspace e±1` ou l'ordre des points) |
| Apps épinglées | fenêtre suivante / précédente de l'app (comme aujourd'hui au clic, mais au scroll) ; app fermée → rien, infobulle « fermée » |
| Cluster apps en cours | **défile la liste** : les apps masquées deviennent accessibles (remplacer le « +N » figé par une fenêtre glissante de N visibles + indicateur de position) |
| Volume | ±5 % (existe, garder) |
| Horloge | mois −1/+1 est déjà sur la popup ; laisser la barre sans molette |

Contraintes : pas de scroll « caché » (l'utilisateur doit voir qu'il y a du contenu au-delà :
points de position ou dégradé), et la molette ne doit jamais déclencher deux actions à la fois
(une seule zone par pixel).

## 3. Épingler / détacher une app — dans la barre

Aujourd'hui `bar.json` est la source, mais on ne peut pas choisir une app depuis l'interface.

- **Bouton « + »** en bas de la pile d'apps épinglées (même gabarit que les autres blocs) →
  popup « Ajouter une app » : champ de recherche + liste des applications installées
  (source : `appindex.py --json`, entrées `apps` triées par nom), chaque ligne avec son icône.
  Clic sur une ligne → ajoute dans `bar.json` (`apps[]` : `id`, `desktop`, `class`, `enabled`) et
  referme la popup. La barre se recharge à chaud (mécanisme `FileView` déjà en place).
- **Clic droit sur une app épinglée** → petite entrée « Détacher » (écrit `enabled: false` ou retire
  l'entrée), **clic droit sur une app en cours** → « Épingler » (réutilise la classe/desktop résolus).
- **Écriture de `bar.json`** : jamais un `JSON.stringify` qui écrase les commentaires ou l'ordre ;
  réécriture atomique (fichier temporaire + `rename`), indentation conservée, et **rien d'autre que
  la section `apps` ne bouge**. Si le fichier est en lecture seule ou invalide → message clair, aucune
  écriture partielle.
- Aucune app en double : ajouter une app déjà épinglée la réactive (`enabled: true`) au lieu de créer
  une seconde entrée.

## 4. État « actif » d'une app épinglée — ne marche pas correctement

`AppDock` fait `active: Hypr.countOf(cls) > 0` avec la classe **écrite dans `bar.json`**
(`"Spotify"`, `"org.kde.dolphin"`) alors que les fenêtres exposent `spotify` / `org.kde.dolphin`.
La comparaison repose donc sur la casse et sur la façon dont l'utilisateur a saisi le nom.

- Résoudre l'état actif par **normalisation des deux côtés** (`norm()` déjà dans `Hypr.qml` :
  minuscules + suppression des non-alphanumériques) et, en second recours, par l'**id du `.desktop`**.
- L'état actif doit être **visible, pas subtil** : barre d'accent latérale + glyphe en couleur d'accent
  + fond `blockActive`. Aujourd'hui, avec un panneau à 0.24 d'alpha, `blockActive` (0.34) se confond
  presque avec le fond : monter l'écart, quitte à ajouter un contour d'accent au lieu d'un fond.
- Même correction pour le cluster « en cours » et pour la pastille de comptage (le badge ne doit pas
  être le seul indice).
- Expose l'état calculé dans `bar.state()` (IPC) : `pinnedOpen: {id: true/false}` — preuve lisible
  par une commande, même si momo teste visuellement.

## 5. Centrage des glyphes (wifi / son / DND, et les autres)

Les 3 cibles de `QuickToggles` sont empilées dans une pilule de 3 × 38 px ; chaque glyphe est centré
individuellement, or les glyphes Nerd Font n'ont pas les mêmes métriques → l'icône wifi paraît
décalée verticalement dans sa case.

- Centrer sur la **case de 38 px**, pas sur le glyphe : `Text` avec `horizontalAlignment`/
  `verticalAlignment` imposés + `anchors.centerIn` sur la case, ou compensation explicite par glyphe
  (`TextMetrics.tightBoundingRect`) documentée en commentaire.
- Vérifier les autres modules de la même façon : loupe, horloge (chiffres), débit (↑/↓ + valeur),
  engrenage, pastilles d'apps, « + » d'épinglage, croix des popups.
- Preuve statique attendue : pour chaque glyphe, la valeur de compensation et le centre calculé
  (case 38 → centre 19) listés dans le rapport. La vérification visuelle sera faite par momo.

## 6. Paramètres

L'engrenage ouvre bien `~/.config/settings/settings.sh` (v2, vérifié). Le garder. Il passe aussi au
contrôle de centrage du §5. **Ne pas** ajouter d'onglet « Barre » au panneau Settings : momo a tranché
— les options de la barre vivent dans la barre et dans `bar.json`.

---

## 7. Contraintes inchangées

- Aucune couleur en dur hors `BarPalette.qml` (tokens dérivés commentés).
- `bar.json` = seule source des options, rechargement à chaud, JSON cassé = config précédente gardée.
- `bar.sh` continue de passer par `systemctl --user start/stop sasquatch-bar`.
- `qmllint` après chaque édition QML, commentaires `//` uniquement, `bash -n`/`py_compile` sur les scripts.
- Ne pas toucher `cc/main.qml`, `cc/sidebar/`, `cc/server.py`, `settings/`, `theme-apply.py`, `waybar/`,
  ni `~/.config/rofi/` (on l'appelle, on ne le modifie pas).
- Pas de grab clavier ; la barre reste utilisable backend éteint (états « indisponible »).

## 8. Rapport attendu (statique uniquement)

1. Fichiers modifiés + `git status --short`, avec staging explicite **fichier par fichier**
   (le dépôt porte des modifications de momo qui ne doivent pas être emportées).
2. `qmllint` sur tous les `.qml` (sortie), `bash -n`, `py_compile`.
3. Tableau §2 « module → molette → action ».
4. Tableau §5 « glyphe → case → compensation → centre calculé ».
5. Le format exact écrit dans `bar.json` quand on épingle/détache (avant/après d'un exemple).
6. **Checklist de vérification pour momo**, exécutable en 2 minutes, une ligne par point :
   loupe (le rofi du dotfile s'ouvre, thème chargé), molette sur chaque module, app épinglée qui
   s'allume à l'ouverture, épinglage puis détachement d'une app, « + » qui liste les apps,
   centrage à l'œil. Avec la commande à lancer (`systemctl --user restart sasquatch-bar`) en tête.
7. Ce qui n'a pas pu être prouvé sans toucher au bureau, et pourquoi.
