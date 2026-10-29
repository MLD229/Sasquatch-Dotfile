# BRIEF Rin — AIKO v2 : sidebar gauche + LLM local éphémère (repartir de zéro)

Date : 2026-10-29
Auteur : Asuka — demande directe de momo
Destinataire : Rin (code)

## DEMANDE (momo, verbatim, reformulé)
« Reprendre à quasi zéro le fichier aiko, comme la sidebar qu'on vient de
faire (verre), mais équipée de plusieurs features. Le but principal : une
sidebar qui charge vite un **LLM local** et le **décharge en fermant**, qui
sert d'assistant commandes / questions simples sur le dotfile ou hors sujet,
**sans mémoire**. Une fois la sidebar (à GAUCHE) fermée, plus rien ne tourne.
Donc utiliser un truc rapide — ollama, un service rapide, ou directement
llama.cpp — et changer le modèle local au besoin : lightweight, rapide à
charger/décharger. Style comme l'autre sidebar. Pas de mémoire persistante :
tout disparaît en fermant. **Repartir à zéro, tout refaire.** »

## DÉCISIONS DÉJÀ PRISES (consultation ChatGPT + mesures machine)

Machine : GTX 1660 Ti **6 Go VRAM**, 15 Go RAM, 8 cœurs. Arch.
Paquets dispo : `extra/llama-cpp` 0.6.0, `extra/ollama` 0.40.13.

**Moteur retenu : `llama-server` (llama.cpp), lancé à la demande, TUÉ à la
fermeture.** Pas ollama : son daemon reste résident, ce qui viole « plus rien
ne tourne ». Avec llama-server, la fermeture = plus de process, VRAM rendue.

**Modèles (GGUF, bartowski) — deux profils :**
| Profil | Fichier | Taille | Usage |
|---|---|---|---|
| `rapide` (défaut) | `Qwen2.5-3B-Instruct-Q4_K_M.gguf` | ~1.9 Go | questions courtes, commandes shell |
| `best` | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | ~4.7 Go | meilleur suivi d'instructions, marge VRAM faible (jeu) |

**Paramètres llama-server** : `-c 4096 -ngl 99 -t 6 --flash-attn on`
(`--no-warmup` à tester seulement si le cold start prime).
Cold start attendu : **1–5 s (3B)**, 3–10 s (7B) → mesurer jusqu'au **premier token**.

**Pièges connus (à implémenter, pas à découvrir) :**
1. Le port HTTP peut répondre **avant** que le modèle soit prêt → attendre
   `/health` (ou une réponse valide) avec timeout avant d'activer l'envoi.
2. Un arrêt de process ne remet pas la VRAM à « exactement 0 » côté pilote :
   vérifier `pgrep llama-server` = vide, c'est la preuve retenue.
3. Ne JAMAIS exécuter une commande suggérée : on l'affiche, l'utilisateur copie
   (garde-fou sudo/rm/redirections).

## ARCHITECTURE DEMANDÉE (from scratch — l'ancien aiko est remplacé)

```
~/.config/aiko/
  shell.qml          sidebar GAUCHE (PanelWindow ancré à gauche, verre)
  aiko.sh            toggle (Super+N) — même robustesse que cc/sidebar/sidebar.sh
  server.py          backend HTTP (port 8791) : chat streaming + cycle de vie LLM
  llm.py             gestion du process llama-server (start/stop/health/model)
  aiko.service       service user — ATTENTION : il ne doit PAS garder le modèle
  installer.sh       vérif paquets + téléchargement des GGUF dans ~/models
  models.json        profils de modèles (rapide / best) + chemins
  README.md
```

### Cycle de vie — cœur du sujet
- **Ouverture** : rien n'est chargé. La sidebar s'affiche instantanément
  (poids plume : QML + un backend Python, pas de modèle).
- **1er message** : le backend démarre `llama-server`, attend `/health`,
  puis streame la réponse. Afficher un état clair : `chargement du modèle…`
  (avec le temps), puis `prêt · 3B` + tokens/s.
- **Fermeture** (Échap, Super+N, clic hors panneau) : le QML appelle
  `POST /api/shutdown` → le backend **tue llama-server** (SIGTERM puis SIGKILL
  après 3 s) → vérifie `pgrep` vide → l'historique en RAM est jeté → le
  backend peut rester (léger) OU s'arrêter aussi : **ton choix, mais dis-le**.
  Contrainte : plus aucun process lourd, plus de VRAM.
- **Inactivité** : si aucun message pendant N minutes (défaut 5), tuer
  llama-server automatiquement (le backend reste léger).
- **Fermeture pendant génération** : annuler proprement (arrêter le stream
  côté serveur) puis tuer le process.

### Fonctionnalités de la sidebar (plusieurs, mais sobres)
1. **Chat** : saisie en bas, streaming token par token, bouton **Stop**,
   bouton **Nouvelle conversation** (vide l'historique RAM).
2. **Historique volatile** : conversations en mémoire uniquement, perdues à la
   fermeture. **Aucun fichier d'état** — c'est une exigence, pas une option.
3. **Sélecteur de modèle** : `rapide` / `best` ; le changement tue le process
   et le relance au message suivant. Affiche le modèle actif + VRAM utilisée si
   disponible (`nvidia-smi`).
4. **Suggestion de commande** : le prompt système demande de rendre les
   commandes dans un bloc ```bash```; l'UI affiche un bouton **copier** —
   **jamais** d'exécution.
5. **Contexte dotfile** : bouton « injecter le contexte » qui joint un court
   résumé statique (chemins des configs : hypr/, kitty/, fish/, waybar/,
   mako/, cc/sidebar/) — PAS une lecture récursive, un digest de quelques
   lignes, pour rester dans le contexte 4k.
6. **Indicateurs** : état moteur (déchargé / chargement / prêt), modèle,
   tokens/s, et un rappel visible « rien n'est conservé ».

### Style
- **Réutiliser la même identité que `cc/sidebar`** : palette issue de
  `cc/qml/Palette.qml`, verre dépoli (`BackgroundEffect`), tokens glass*,
  boutons à 4 états, animations `OutCubic` sobres.
- Panneau **ancré à GAUCHE**, largeur ~420 px, `exclusiveZone: 0` (overlay).
- **Aucun grab clavier** (`SASQUATCH_SIDEBAR_NOGRAB=1` équivalent) : le grab a
  déjà bloqué hyprlock une fois.

## PRÉREQUIS (à vérifier, pas à installer toi-même)
- `llama-cpp` (fournit `llama-server`) : **absent** → momo doit lancer
  `sudo pacman -S llama-cpp`. Ton `installer.sh` le détecte et affiche la ligne
  exacte s'il manque.
- Modèles : tu peux les **télécharger sans sudo** dans `~/models/`
  (Hugging Face, bartowski). Si le réseau bloque, écris le script + la commande
  exacte, ne prétends pas les avoir.

## RÈGLES
- **Repartir de zéro** : l'ancien `main.qml` d'aiko est remplacé (garde une
  copie dans `_archive/` si tu veux, mais il ne doit plus être chargé).
- Le keybind `Super+N` doit continuer à marcher (pointe vers `aiko.sh`).
- **Aucune persistance** : pas de fichier d'état, pas de log de conversation
  sur disque (les logs techniques oui, mais sans contenu utilisateur).
- Ne pas toucher `cc/sidebar` (l'autre panneau) — tu peux t'en inspirer.
- Pas de commit (momo valide).

## VÉRIFICATION (session Hyprland disponible)
Env : `XDG_RUNTIME_DIR=/run/user/1000`, `WAYLAND_DISPLAY=wayland-1`,
`HYPRLAND_INSTANCE_SIGNATURE=<ls -t /run/user/1000/hypr | head -1>`, `DISPLAY=:0`.
1. `qmllint` sur tous tes QML + `python3 -m py_compile` sur les .py.
2. Lance la sidebar : `hyprctl layers | grep quickshell` (ancrée à gauche) +
   capture `grim -g "<x>,<y> <w>x<h>"` et **regarde l'image**.
3. **Preuve du cycle de vie** (le plus important) :
   - avant ouverture : `pgrep -c llama-server` = 0 ;
   - après le 1er message : = 1, et `/health` OK avant la 1re génération ;
   - après fermeture : **= 0** (colle la sortie) et l'historique a disparu ;
   - inactivité : tuer après le délai (teste avec un délai court).
4. Streaming réel : colle un extrait de réponse arrivé par morceaux (pas
   d'un coup) + le temps jusqu'au premier token.
5. Aucun fichier d'état créé : `ls -la ~/.local/state/aiko 2>/dev/null` vide.
6. Ce qui n'a pas pu être testé (ex. si `llama-cpp` manque), honnêtement.

## LIVRABLE
Fichiers, sorties réelles, mesures (cold start, tokens/s), limites, et la
commande unique pour ouvrir la sidebar.
