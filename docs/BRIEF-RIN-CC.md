# Brief — CC Sasquatch : dashboard façon capture + outils en pages

Dépôt réel : `/home/momo/Downloads/Sasquatch-Dotfile` (cible des symlinks).
Capture de référence (à ouvrir avec ton outil vision) : `docs/ref-cc-dashboard.png`.

## Demande de momo

« j'aimerais un style comme l'image mais d'abord l'analyser et retirer les informations les
différentes parties et plugins etc ensuite travailler dessus » → le Home devient un **dashboard**
comme la capture ; les outils actuels ne disparaissent pas, ils passent en **pages** de la nav.

## Ce qu'il y a dans la capture (structure à reproduire)

- **Barre de nav** en haut : pastille logo+nom à gauche, au centre une pastille « Home » active +
  des boutons d'icônes pour les pages, à droite recherche / notifications / avatar rond.
- **Colonne gauche (large)** : « Bonsoir » + « allumé depuis • 3j 0h 52m », puis carte **profil** :
  avatar, `user@host`, et 5 lignes avec icône : distribution, CPU, GPU, noyau, shell.
- **Colonne milieu** : carte **mises à jour** (nombre, Pacman • AUR, boutons « Mettre à jour » et
  « Mettre à jour les dots »), puis **calendrier** (mois + grille, jour courant en accent).
- **Colonne droite** : carte **horloge + météo** (heure, ville, condition, température, en aplat
  accentué) puis carte **tâches** (fait/total, état vide « rien à faire », bouton +).

Style : cartes très arrondies (rayon ~16), translucides, palette générée (aucun hex en dur),
une seule famille d'accent, titres de carte en petites capitales, beaucoup d'air.

## Données : les routes existent DÉJÀ (backend vérifié)

- `GET /api/sysinfo` → `{user, host, distro, kernel, shell, cpu, cores, gpu, uptime, uptime_s, hour}`
- `GET /api/updates` → `{pacman, aur, total, ok, erreur, verifie, age_s}` (cache 15 min)
- `GET /api/weather?city=Lyon` → `{ok, city, temp, code, label, lat, lon, age_s}` (cache 10 min)
- `GET /api/tasks` → `{items:[{id,text,done,at}], total, done}`
- `POST /api/tasks` `{action:"add",text}` · `{action:"toggle",id}` · `{action:"remove",id}` ·
  `{action:"clear"}` — testé à la main : add/list/toggle/remove OK, fichier
  `~/.local/state/sasquatch-cc/tasks.json`.
- Déjà là et à conserver : `/api/stats`, `/api/music/*`, `/api/playlist/*`, `/api/wallpaper*`,
  `/api/viz`, `/api/translate`, `/api/screenshot`, `/api/imgsearch`, `/api/system/volume|brightness`.

## Tâche 1 — Home dashboard

Réécrire la page Home de `cc/main.qml` en trois colonnes comme la capture, alimentée par les routes
ci-dessus. Carte horloge : heure locale + `hour` pour la salutation (« Bonne nuit / Bonjour /
Bonsoir »), météo via `/api/weather`. Calendrier : pur QML (date locale), grille 7×6, jour courant
en accent. Tâches : liste + ajout + cocher + supprimer via `POST /api/tasks`, compteur fait/total.

## Tâche 2 — les outils deviennent des pages (RIEN ne doit disparaître)

Les blocs actuels de `main.qml` passent dans des pages séparées, chacune gardant **son code et ses
appels API intacts** : `Musique` (lecteur + viz), `Playlist`, `Papier peint`, `Performance`
(jauges), `Capture`, `Reconnaître` (dictée), `Recherche image`, `Traduction`.
- Une seule page visible à la fois ; la nav (Home + un bouton par page + engrenage) pilote.
- L'engrenage ouvre `~/.config/settings/settings.sh` (fenêtre « Sasquatch Settings », port 8770).
- Échap ferme le CC (comportement actuel à conserver), pas de grab clavier.

## Contraintes dures

1. **Ne rien lancer sur le bureau de momo** : pas de `cc.sh`, pas de `quickshell -p`, pas de
   `systemctl restart sasquatch-cc` (le backend tourne et sert déjà les routes). Vérification
   statique + `curl` uniquement.
2. Palette **générée** (`cc/qml/Palette.qml`, `read_palette()`) : aucun `#rrggbb` hors repli
   commenté. Le CC suit le papier peint.
3. `qmllint` **Qt6** sur chaque QML touché : `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml <f>`.
   `python3 -m py_compile` si tu touches un `.py`.
4. Ne pas casser les routes : après édition, `grep -oE '"/api/[a-z0-9/_-]+"' cc/main.qml | sort -u`
   doit toujours contenir chaque route utilisée avant (liste-les dans le rapport, avant/après).
5. Un commit par tâche, `git add` explicite (le dépôt contient des modifs non commitées de momo :
   liste celles que tu laisses).
6. Aucune dépendance Python en plus (stdlib), aucun paquet système nouveau.

## Livrable (rapport)

- fichiers modifiés/créés + `wc -l`,
- sortie `qmllint` Qt6 (0 erreur attendu) et `py_compile`,
- la liste **avant/après** des routes `/api/…` utilisées par `main.qml`,
- les `curl` de contrôle que tu as lancés (sysinfo/updates/weather/tasks) avec leur sortie,
- la checklist pour momo : ouvrir le CC (Super+G), vérifier Home, passer sur chaque page, fermer,
- ce qui n'a pas pu être vérifié sans lancer l'interface, et le premier endroit à regarder si un
  bloc ne s'affiche pas.
