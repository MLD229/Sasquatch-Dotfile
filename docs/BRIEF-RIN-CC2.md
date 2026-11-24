# Brief — CC v6.1 : musique sur l'accueil, outils réparés, conflits

Dépôt réel : `/home/momo/Downloads/Sasquatch-Dotfile` (cible des symlinks `~/.config/cc`).
État actuel (commit `1478135`) : `cc/Dashboard.qml` (page Accueil, 461 l.) + `cc/main.qml`
(929 l.) avec nav `Accueil / Système / Outils` ; les rangées existantes sont **conservées** et
seulement masquées par page. Backend : `cc/server.py` (+ `cc/sysinfo.py`), routes vérifiées :
`/api/sysinfo`, `/api/updates`, `/api/weather`, `/api/tasks`, plus tout l'existant
(music, playlist, wallpaper, viz, translate, screenshot, imgsearch, volume/brightness).

## 1) Le lecteur musique sur l'ACCUEIL

Déplacer (pas dupliquer) le bloc **musique** — pochette, titre/artiste, play/pause, précédent/
suivant, barre de progression, visualiseur `viz` si peu coûteux — de la page « Système » vers
`cc/Dashboard.qml`, dans la **colonne 1**, sous la carte profil. Contraintes :
- une **seule** instance du lecteur dans tout le CC (aucun timer/abonnement en double) ;
- mêmes données qu'aujourd'hui : `/api/music/status` (poll 1 s max) et actions
  `/api/music/toggle|next|prev|seek` (POST `{v:secondes}` pour seek) ;
- la page « Système » garde PERFORMANCE (jauges) et perd le lecteur ;
- si `playing=false`, la carte doit rester compacte (pas de grand vide).

## 2) Réparer les outils

Page « Outils » actuelle : CAPTURE, RECONNAÎTRE (dictée), RECHERCHE IMAGE, TRADUCTION.
Pour **chacun** : vérifier le chemin complet `bouton → route → script` et corriger ce qui est
cassé. Contrôles attendus (statique, sans lancer l'UI) :
- `curl` la route avec un corps réaliste (ou `--help` du script sous-jacent) et noter le code ;
- vérifier que le bouton du QML appelle exactement la route existante (`grep -oE '"/api/[a-z0-9/_-]+"'`) ;
- une dépendance absente (`tesseract`, `wl-copy`, `ffmpeg`, `grim`, `slurp`…) doit produire un
  message visible dans l'UI, jamais un bouton muet : `command -v` et libellé « non installé » ;
- aucune commande shell construite par concaténation d'entrée utilisateur sans échappement.

Si un outil n'a plus de backend (route absente), soit tu le relies à la route existante, soit tu
le marques « indisponible » avec la raison — ne laisse pas un bouton qui ne fait rien.

## 3) Chasse aux problèmes / conflits

- **Palette** : aucun `#rrggbb` hors repli commenté ; tout passe par `cCard/cText/cAccent…`.
- **Identifiants QML** : aucune collision d'`id` entre `main.qml` et `Dashboard.qml`.
- **Timers** : pas deux pollers pour la même route (musique 1 s, stats 1 s, dash 60 s, updates 15 min).
- **Doublons de composants** : le CC n'a qu'un lecteur, qu'une barre de nav, qu'un footer.
- **Ports** : backend CC = 8765, réglages = 8770, barre = pas de port. Aucun nouveau port.
- **Fichiers d'état** : `~/.local/state/sasquatch-cc/tasks.json` (écriture atomique), rien d'autre.
- **`qmllint` Qt6** propre sur `main.qml` et `Dashboard.qml` ; `python3 -m py_compile` si `.py` touché.
- Si tu trouves un conflit que tu ne peux pas trancher sans momo, **liste-le** au lieu de choisir.

## Contraintes dures

1. **Ne rien lancer sur le bureau** : ni `cc.sh`, ni `quickshell -p`, ni `systemctl restart
   sasquatch-cc`. Vérification statique + `curl` seulement (le backend tourne déjà).
2. Palette générée, aucune dépendance nouvelle, aucun paquet système.
3. Un commit par point (musique / outils / conflits), `git add` explicite, et liste les fichiers
   de momo que tu laisses non commités.
4. Ne supprime aucun bloc existant : déplacement ou masquage uniquement.

## Livrable

- fichiers modifiés + `wc -l`, `qmllint` (0 erreur), `py_compile` ;
- tableau outils : outil → route → `curl` (code + extrait) → état (OK / réparé / indisponible+raison) ;
- liste des conflits trouvés et de ce que tu as corrigé (ou laissé, avec la question) ;
- checklist pour momo : Super+G, vérifier la musique sur Accueil, puis chaque outil, puis fermer.
