# BRIEF rin — CC : les outils (Outils / capture·finder·imgsearch·translate) — check + réparation + peaufinage

Demande de momo : « mettre en place ou réparer les outils du cc — check, puis peaufinage ».
Repo `~/Downloads/Sasquatch-Dotfile/cc` = `~/.config/cc` (les deux sont **identiques**, 0 diff, vérifié).
Backend = unité user `sasquatch-cc.service` (port 127.0.0.1:8765, `Restart=always`).

## 0. Faits déjà mesurés sur la machine (ne pas re-litiger)

- Service `active (running)`, 3 h 18 d'uptime, RSS 548 Mo (**pic 1,3 Go**), CPU 20 min cumulées.
- `GET /api/tools/health` → `capture`, `finder`, `imgsearch`, `translate` tous `ok: true`, `manque: []`.
  ⚠️ Ce check est **`shutil.which` seulement** (`cc/actions.py:391`) : il prouve la présence des binaires,
  **pas** que l'outil fonctionne.
- Routes lues en 200 avec du contenu réel : `sysinfo`, `stats`, `weather` (Lyon 7 °C), `updates` (7 aur),
  `notes` (0 note), `music/status`, `playlist/status`, `wallpapers` (151 Ko).
- `GET /api/state` et `/api/env` → **404 : ces routes n'existent pas dans ce backend**. Ne pas les chercher.
- `qmllint` **Qt6** (`/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I cc/widgets`) :
  `main.qml` **propre** ; `pages/StudioPage.qml` → ~8 `Unqualified access` (lignes ~816-875).
- Journal : `BrokenPipeError` / `ConnectionResetError` + traceback Python à répétition
  (`flush_headers`), à chaque client QML qui coupe sa requête.
- `12` fichiers modifiés **non commités** dans `cc/` (825+/76-) : `apply-wallpaper.sh`, `autoplace.py`,
  `main.qml`, `StudioPage.qml`, `widgets.json`, `Theme.qml`, `WidgetBase.qml`, `WidgetCanvas.qml`,
  `ClockWidget.qml`, `registry.json`, `widgets_json.py`, `cava.conf`. **Ce n'est pas à toi de les
  commiter** — voir §4.

## 1. Audit fonctionnel des 4 outils (priorité 1)

Prouver chaque chemin de bout en bout, sur la session live, **sans jamais ouvrir le CC plein écran** :
harnais 900×620 (cf. skill, `references/widgets-placement`/harnais existant), une seule instance, pkill
**crocheté**, chemin absolu + `hyprctl dispatch exec` pour lancer.

- `capture` (`/api/screenshot`) : les 3 modes (zone / fenêtre / écran). Vérifier que le fichier est écrit,
  non vide, et que la réponse renvoie un chemin valide. La sélection de zone se teste avec un
  `slurp` scripté ou une géométrie imposée — pas en cliquant.
- `finder` (reconnaissance musicale) : dépend d'un enregistreur (`ffmpeg`/`pw-record`/`arecord`) puis du
  service de reco. Tester avec **5 s** d'audio, prouver la réponse et le cas « pas de résultat ».
- `imgsearch` (mot-clé + zone écran → texte → images) : les deux chemins. Le repli texte (OCR) doit être
  testé même quand la recherche web est indisponible.
- `translate` (sélection de zone → OCR → traduction) : chemin complet + cas d'échec (aucun texte détecté,
  réseau coupé) — chaque échec doit sortir un message lisible, jamais un bouton muet.

Pour chaque outil : une ligne `outil → commande → sortie réelle → OK/KO`.

## 2. Réparations attendues (défauts constatés)

1. **Tracebacks HTTP** : `BrokenPipeError` / `ConnectionResetError` dans `server.py` (handler +
   `flush_headers`). Un client qui coupe ne doit produire **ni traceback ni silence** : une ligne de log
   max, `log_message` filtré. Preuve : 20 requêtes coupées volontairement (`curl -m 0.05`) → plus aucun
   `Traceback` dans `journalctl --user -u sasquatch-cc -n 50`.
2. **`/api/tools/health` trop faible** : ajouter, en plus de `which`, un test d'exécutabilité léger
   (`--version`/`-h`, timeout court, résultat mis en cache) pour que la page Outils dise vrai quand un
   binaire existe mais est cassé.
3. **RSS 548 Mo (pic 1,3 Go)** : identifier ce qui gonfle (caches de pochettes ? historique ? buffers
   d'images ?), mesurer avant/après, plafonner. Si c'est un cache assumé, le documenter en une ligne et
   borner sa taille.
4. Ce que l'audit du §1 révèle — même règle : symptôme → cause → correctif → preuve.

## 3. Peaufinage mesuré (pas de refonte)

- `StudioPage.qml` : supprimer les `Unqualified access` (qualifier les identifiants, ou `pragma ComponentBehavior`), sans changer le comportement ni la mise en page.
- Cohérence de la page Outils avec le backend : chaque état (`ok`, manque, hint pacman) doit rester rendu pour les 4 outils après tes modifs.
- Aucun hex en dur ajouté : la palette reste générée (`qml/Palette.qml` / `/api/palette`).

## 4. Interdits (un run qui les viole est un échec)

- **Ne pas commiter** les 12 fichiers modifiés de `cc/`, ni `git add -A`, ni `git stash`. Tu peux
  commiter **uniquement** les fichiers que tu as toi-même touchés, avec des chemins explicites, et
  seulement si tu le dis dans le rapport.
- Ne pas lancer le CC en plein écran : un `FloatingWindow` plein écran avale les clics de momo.
- Ne pas toucher `cc/apply-wallpaper.sh` ni le générateur de thème (`~/.config/scripts/theme-apply.py`).
- Ne pas réécrire `pages/HomePage.qml`, `SystemPage.qml`, `ToolsPage.qml` : ce sont les pages de momo.
- Pas de `pkill -f` non crocheté, pas de démon lancé `&` depuis le service (il meurt avec le cgroup).
- Pas de nouvelle dépendance système (pas de `sudo`, pas de `pacman`).

## 5. Cadence et preuves

**Code d'abord, UN seul passage de vérification à la fin** : `qmllint` Qt6, `systemctl --user restart
sasquatch-cc` + `is-active`, un `curl` par route touchée. Pas de cycles de rendu successifs ; si une
preuve est impossible (pas de sélection graphique scriptable), l'écrire et avancer. Si un run dépasse
~20 min, livrer l'état sur disque et le rapport partiel plutôt que de relancer des captures.

Rapport final court, en français :
`| outil | état | preuve (commande + sortie) |` + `| symptôme | cause | correctif | preuve |` +
la liste des fichiers touchés + ce qui reste ouvert.
