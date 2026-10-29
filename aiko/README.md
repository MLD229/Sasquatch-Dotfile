# 愛子 (Aiko) v2 — sidebar gauche + LLM local éphémère

Panneau **ancré à gauche**, style verre (identique à `cc/sidebar`), qui répond
avec un **LLM local** chargé au premier message et **tué à la fermeture**.
La conversation n'est jamais écrite : elle vit en RAM et disparaît quand on
ferme. Seule exception, voulue : le **choix 3B/7B** est mémorisé
(`~/.local/state/aiko/prefs.json`) pour être rechargé à la réouverture.

```
Super+N   →  ouvre / ferme            (ou ~/.config/aiko/aiko.sh)
Échap     →  ferme et décharge le modèle
Ctrl+N    →  nouvelle conversation (vide la RAM)
3B / 7B   →  change de modèle : écrit la préférence puis tue le process
```

```
~/.config/aiko/            (lien vers Sasquatch-Dotfile/aiko)
  shell.qml                PanelWindow GAUCHE, verre, 420 px, exclusiveZone 0
  qml/GlassButton.qml      bouton verre 4 états (repos/survol/pressé/actif)
  server.py                backend HTTP 8791 : chat NDJSON + cycle de vie + prefs
  llm.py                   process llama-server : start / health / stop / stream
  aiko.sh                  toggle Super+N (source de vérité du cycle de vie)
  installer.sh             vérifs prérequis + téléchargement des GGUF
  models.json              profils « rapide » (3B) et « best » (7B)
  aiko.service             service user FACULTATIF (jamais activé, voir plus bas)
  tests/lifecycle_test.py  cycle de vie complet (25 assertions)
  tests/prefs_test.py      le modèle choisi survit à une réouverture (16 assertions)
  tests/conflicts_test.py  conflits provoqués : double backend, ports, arrêt (26 assertions)
  tests/capture.sh         capture du panneau (session déverrouillée)
  _archive/                ancien aiko (main.qml, server.py) — plus chargé
```

## Le contrat de cycle de vie (mesuré)

| Étape | Ce qui tourne | Mesure réelle (GTX 1660 Ti, Vulkan, 3B) |
|---|---|---|
| Ouverture (Super+N) | quickshell + `server.py` (~35 Mo) | panneau affiché < 100 ms |
| 1er message | + `llama-server` | cold start **1,22 s** (cache chaud) à ~7 s (disque froid), 1er token **1,58 s** |
| Génération | `llama-server` | **82,7 tok/s**, VRAM du modèle **2 074 MiB** |
| Inactivité (5 min) | modèle tué, backend léger | vérifié avec `AIKO_IDLE_SEC=6` |
| Fermeture | **rien** | llama mort en **0,24 s**, VRAM **2 077 → 3 MiB** |

Preuve retenue pour « plus rien ne tourne » :
`pgrep -f '[a]iko-ephemere'` = **0**, `pgrep -x llama-server` = **0**,
port 8791 fermé, `hyprctl layers` sans `namespace: aiko`.

**Décision assumée** : à la fermeture le backend Python **s'arrête aussi**
(`POST /api/shutdown` → tue llama-server → jette l'historique → `os._exit`).
C'est le seul moyen d'avoir littéralement zéro process. Coût : ~50 ms de
python au prochain `Super+N`, négligeable devant le panneau.

## Une seule source de vérité (et pas deux backends)

| Question | Réponse |
|---|---|
| Qui démarre le backend ? | `aiko.sh` (à la demande) ; un backend déjà vivant est **réutilisé**, jamais doublonné |
| Et `aiko.service` ? | **facultatif, jamais activé** : il ne fait que pré-ouvrir le port. S'il tourne, `aiko.sh` le détecte (`systemctl --user is-active`) et s'en sert |
| Deux `server.py` en même temps ? | impossible : `flock` exclusif sur `$XDG_RUNTIME_DIR/aiko/backend.lock`, le second sort avec un message clair (code 0) |
| Deux pressions de Super+N en même temps ? | sérialisées par un `flock` sur `$XDG_RUNTIME_DIR/aiko/toggle.lock` |
| Deux panneaux aiko ? | impossible : le toggle ferme l'existant ; un résidu est tué avant l'ouverture |
| aiko + `cc/sidebar` (Super+U) ensemble ? | vérifié en session réelle : les deux panneaux ouverts en même temps (aiko à **80,9 tok/s** à côté), puis fermeture d'aiko → le panneau de droite reste ouvert. Les motifs `pgrep` ne se croisent pas (`aiko/shell.qml` ≠ `sidebar/shell.qml`) |
| Fermeture quand c'est le **service** qui tient le backend ? | `aiko.sh` fait `systemctl --user stop aiko` — **jamais** `pkill -KILL` : un SIGKILL est vu comme un échec par systemd et `Restart=on-failure` relance le backend (vécu : `status=9/KILL` → « Scheduled restart job », NRestarts=1). Mesuré après correctif : `Stopped`, `ExecMainStatus=0`, `NRestarts=0`, journal propre |
| 8791 déjà pris par autre chose ? | `aiko.sh` refuse d'ouvrir + notification expliquant quoi regarder ; `server.py` sort en code 2 (**pas de traceback**) |
| 8792 déjà pris ? | le chat renvoie une erreur qui **nomme le port et son occupant** (`ss -ltnp`), le backend reste debout |
| Modèle GGUF absent ? | message UI avec la **commande curl exacte**, pas de crash |
| `llama-server` absent ? | message UI : build Vulkan (80 tok/s) ou paquet Arch CPU seul (12,8 tok/s) |
| Fermeture **pendant** le cold start ? | drapeau `abort` + kill par marqueur : réponse en **0,07 s**, 0 orphelin (vérifié par `tests/conflicts_test.py`) |

## Cycle de vie côté code

- `llm.py::start()` lance `llama-server`, puis **poll `/health`** (le port HTTP
  répond souvent *avant* que le modèle soit prêt — piège n°1 du brief).
- `llm.py::stop()` : `abort` posé d'abord, `SIGTERM` au **groupe**, `SIGKILL`
  après 3 s, puis re-vérifie `pgrep` et rend la VRAM. Il ne bloque pas un
  chargement en cours : le process candidat n'est pas encore publié, donc il
  est retrouvé par le **marqueur `aiko-ephemere`** de son argv.
- Tuer le modèle ≠ perdre la conversation : l'historique est dans la RAM de
  `server.py` (ListModel côté QML + liste côté backend, bornée à 8 tours /
  6 000 caractères). Il est jeté à `shutdown` et à « nouvelle conversation ».
- **Stop** : `POST /api/stop` ferme la connexion upstream ; llama.cpp détecte
  la déconnexion et arrête la génération, **le modèle reste chargé**
  (vérifié : flux terminé à 86 tokens, `pgrep` = 1).

## Ce qui est écrit sur disque — la SEULE chose persistée

| Fichier | Contenu | Durée de vie |
|---|---|---|
| `~/.local/state/aiko/prefs.json` | `{"model": "rapide"\|"best", "updated": "..."}` — **la préférence de modèle, rien d'autre** | permanente (c'est le but) |
| `~/.cache/aiko-backend.log` | log technique (démarrage/arrêt, jamais le contenu des messages) | écrasé/roulé par le système |
| `~/models/*.gguf` | les modèles (évidemment) | permanente |

**Pourquoi cette exception ?** momo a demandé « retenir le dernier modèle
choisi entre le 3B et le 7B à la réouverture ». Une **préférence** n'est pas
une **mémoire** : le fichier ne contient aucune phrase, aucun tour de
conversation, aucun horodatage de message — seulement un nom de profil.
L'historique, lui, meurt avec le process (vérifié par le test 7 de
`lifecycle_test.py`, qui refuse désormais **tout fichier autre que
`prefs.json`** dans `~/.local/state/aiko`).

Détails d'implémentation :
- écriture **atomique** (`tmp` + `os.replace`), dossier créé au besoin ;
- fichier absent / illisible / corrompu / profil inconnu / GGUF du profil
  disparu → **repli silencieux sur `models.json["default"]`**, la raison part
  dans les logs techniques (`pref_note`), pas dans l'UI ;
- le changement de modèle écrit la préférence **avant** de tuer le process :
  même si le kill échoue, le choix est retenu.

## Sécurité : commandes jamais exécutées

Le prompt système impose les commandes dans des blocs ` ```bash ` ; l'UI les
affiche en monospace vert avec un bouton **copier** (`wl-copy` en argv direct,
sans shell). **Aucun** endpoint n'exécute quoi que ce soit — il n'y a même pas
de code prévu pour ça dans `server.py`.

## GPU : ce qu'il faut savoir (important)

Le paquet Arch `extra/llama-cpp` est **CPU seul** : `llama-server --list-devices`
répond `(none)` → **12,8 tok/s** mesurés sur le 3B.

Pour le GPU (mesures ci-dessus : **82,7 tok/s**), il faut un build Vulkan/CUDA.
Cette machine a un build Vulkan précompilé dans `~/.local/bin/llama-server`
(wrapper vers `~/.local/share/aiko/llama/llama-b11982/`, installé sans sudo).

Ordre de résolution du binaire (`llm.py::find_llama_server`) :
1. `$AIKO_LLAMA_SERVER`
2. `llama-server` du `PATH` (donc `~/.local/bin` s'il existe, sinon `/usr/bin`)
3. le backend livré par LM Studio (`~/.lmstudio/extensions/backends/…`)

Et le périphérique est **épinglé** : cette machine expose `Vulkan0` (Intel iGPU,
mémoire partagée) et `Vulkan1` (GTX 1660 Ti). Sans pin, llama.cpp répartit les
couches sur les deux → plus lent. `llm.py` choisit le premier device dont le
nom contient « nvidia » (surchargeable : `"device": "Vulkan1"` dans
`models.json`).

## Modèles

| Profil | Fichier | Taille | VRAM | Usage |
|---|---|---|---|---|
| `rapide` (défaut) | `Qwen2.5-3B-Instruct-Q4_K_M.gguf` | 1,9 Go | 2 074 MiB | commandes, questions courtes |
| `best` | `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 4,7 Go | 4 491 MiB | meilleur suivi, marge VRAM faible |

Mesures réelles du profil `best` (Vulkan, GTX 1660 Ti) : cold start **12,2 s**
disque froid (**1,82 s** cache chaud), 1er token **13,4 s**, **39,0 tok/s**,
VRAM **4 491 / 6 144 MiB**. Il tient, mais il ne reste que ~1,6 Go de marge :
à éviter si un jeu tourne.

Le sélecteur `3B` / `7B` **écrit la préférence** puis tue le process ; le
modèle est rechargé au message suivant — et au prochain démarrage c'est celui
qui revient. `ctx` = 4096 (3B) / 3072 (7B) : le 7B est volontairement plus
court pour tenir dans 6 Go.

## Commandes

```bash
# ouvrir / fermer (le cycle de vie est dans le script)
~/.config/aiko/aiko.sh          # = Super+N
~/.config/aiko/aiko.sh          # 2e appel = fermeture + déchargement

# installer / vérifier les prérequis (llama-server, GGUF, wl-copy, keybind)
bash ~/.config/aiko/installer.sh            # vérifs + GGUF 3B manquant
bash ~/.config/aiko/installer.sh --check     # vérifs seules
bash ~/.config/aiko/installer.sh --with-7b   # télécharge aussi le 7B

# preuves
python3 ~/.config/aiko/tests/lifecycle_test.py    # 25 assertions, ~40 s
python3 ~/.config/aiko/tests/lifecycle_test.py --quick
python3 ~/.config/aiko/tests/prefs_test.py        # 16 assertions, ~20 s
python3 ~/.config/aiko/tests/conflicts_test.py    # 26 assertions, ~40 s
```

- `lifecycle_test.py` : au repos → 1er message → streaming → Stop →
  inactivité → fermeture → **seule la préférence est persistée**.
- `prefs_test.py` : changement de modèle → `prefs.json` écrit → fermeture →
  réouverture → **le modèle choisi est rechargé** (prouvé par la cmdline du
  `llama-server` vivant et `/api/health`), puis restaure la préférence d'origine.
- `conflicts_test.py` : double backend, port 8791 étranger, port 8792 étranger,
  modèle absent, `llama-server` absent, fermeture pendant le cold start.
  Chaque cas est **provoqué pour de vrai** (vrais process, vrais sockets).

## Réglages

| Variable | Effet |
|---|---|
| `AIKO_IDLE_SEC` | secondes d'inactivité avant déchargement (défaut 300) |
| `AIKO_LLAMA_SERVER` | chemin explicite du binaire `llama-server` |
| `AIKO_MODELS_DIR` | dossier des GGUF (défaut `~/models`) |
| `AIKO_STATE_DIR` | dossier de `prefs.json` (défaut `~/.local/state/aiko`) |
| `AIKO_PORT` | port du backend (défaut 8791) |
| `AIKO_DEBUG=1` | traces HTTP côté backend + tokens côté QML (stdout) |

Ports : **8791** = backend aiko, **8792** = llama-server (loopback seulement).

## Limites connues

- **Mémoire de conversation : aucune.** C'est l'exigence : seuls le choix
  3B/7B et les réglages de profil survivent. Le modèle ne se souvient de rien.
- Le 7B sur 6 Go : si `nvidia-smi` montre autre chose qui occupe la VRAM
  (jeu, autre modèle), le chargement peut échouer → message d'erreur clair,
  le panneau reste utilisable, il suffit de repasser en 3B.
- Pas d'accès web, pas de lecture de fichiers : le « contexte dotfile » est un
  digest statique de quelques lignes (bouton `contexte`).
- Aucun grab clavier : le panneau demande le focus (OnDemand) mais ne le
  capture pas — sur Hyprland 0.56.2 un grab actif bloquait hyprlock. Ça vaut
  aussi pour la coexistence avec `cc/sidebar` (Super+U, droite) : deux
  `PanelWindow` séparés, aucun ne confisque le clavier à l'autre.
- `qmllint` 1.0 (Arch) **sort en 255 sans aucun message** — cause identifiée :
  la ligne `pragma ComponentBehavior: Bound`. Preuve minimale : un fichier
  d'**une seule ligne** contenant ce pragma sort déjà en 255 ; le même fichier
  sans le pragma, avec tous les imports de `aiko` (`QtQuick`,
  `QtQuick.Controls`, `QtQuick.Layouts`, `Quickshell*`) sort en **0**.
  Ce n'est donc ni les imports Quickshell ni ce fichier qui sont cassés —
  `cc/sidebar/shell.qml` (même pragma) échoue à l'identique.
  Le pragma reste nécessaire : les délégués de `Repeater` accèdent à
  `bubble`/`segCol` depuis un composant lié.
  Validation retenue à la place : chargement par quickshell
  (`INFO: Configuration Loaded`, **0 warning** dans `log.qslog` pendant un
  stream complet, vérifié sur capture) + `qmllint` propre (code 0) sur
  `qml/GlassButton.qml`, qui n'a pas le pragma.
- `aiko.sh` est la seule source de vérité ; le `flock` de `toggle.lock` est
  rendu **avant** `exec quickshell` et le backend est lancé avec `9>&-`
  (deux bugs vécus : `exec 9>file 2>/dev/null` masque ensuite toute la sortie
  d'erreur du script, et un backend héritant du fd garde le verrou → tous les
  toggles suivants sont ignorés en silence).
- Cas limite restant sur le service : si `systemctl --user stop` échoue **et**
  que le port répond encore, le filet fait un `pkill -KILL` — dans ce cas
  (très improbable) systemd relancera le backend une fois.
  `systemctl --user stop aiko` à la main remet les choses d'équerre.
- La preuve visuelle (`tests/capture.sh`) exige une session **déverrouillée** :
  hyprlock recouvre tous les outputs, une capture ne montre que la serrure.
- Si `aiko.service` est **activé** à la main, il ne sert qu'à pré-ouvrir le
  port au login : le backend sort proprement à la première fermeture
  (`os._exit(0)`), donc le service repasse `inactive` (avec `Restart=on-failure`
  systemd ne relance pas une sortie propre) et ne revient qu'au login suivant.
  C'est pour ça qu'`install.sh` copie l'unité **sans jamais l'activer** :
  `aiko.sh` gère le cycle de vie.
