# BRIEF — mode `kana` : encre colorée, animations sobres, zéro process en plus

Date : 2026-11-02. Auteur : Asuka. Exécutant : rin.

**RÈGLE : momo travaille sur sa machine. Tu ne lances RIEN.**
Interdits : `systemctl restart/stop/start` (sasquatch-cc, sasquatch-bg, sasquatch-bar), `quickshell -p`,
`cc.sh`, `background.sh`, les harnais (`tests/*.qml`, `tests/*.sh`), `hyprctl dispatch`, `notify-send`,
`qs ipc call`, `POST /api/widgets` (ça écrit dans le `widgets.json` réel de momo), `curl` sur les routes
d'écriture. Autorisé : lire, `grep`, `qmllint` Qt6, `py_compile`, `bash -n`, `git status`.
Toute preuve dynamique est **différée** → checklist en fin de brief, c'est Asuka qui l'exécute.

Lis d'abord : `cc/widgets/Sasquatch/Widgets/Theme.qml` (fonctions `lumAt`, `contrastOn`, `inkOn`,
`inkDimOn`, `accentOn`, `panelAlphaOn`, `lumTimer`), `WidgetBase.qml` (`bgLum`, `ink`, `inkDim`,
`accentInk`), `widgets/ClockWidget.qml` (bloc « Kana »), `cc/widgets.json` (`placement`).

## §0 — Faits déjà mesurés (ne pas re-litiguer)

- Fond courant : `a_cartoon_of_a_monster.png`, luminance moyenne `0.236`. Zones mesurées : carte
  `clock-4` = **0.143**, carte `resources-6` = **0.235** (grille 32×18, valeurs 0..1).
- Palette générée courante : `text = #d2d0cf` (quasi neutre, saturation ≈ 0.01), `accent = #c44227`.
- `GET /api/wallpaper/lumgrid` → `{wallpaper, w: 32, h: 18, values: [576 floats]}`. Pas de flux
  d'événement : aujourd'hui `Theme.lumTimer` **poll toutes les 6 s**.
- `Theme.lightWallpaper` n'est plus qu'une info d'écran ; l'encre des cartes vient de `bgLum` (binding
  posé par `WidgetCanvas`), `-1` = inconnu (hôtes cc/bar/subpage : verre sur panneau → encre palette).
- `widgets.json` porte déjà `placement: {strategy, margin, gap, corner, host, auto}` ; `apply-wallpaper.sh`
  appelle `{"op":"reapply"}` après chaque changement de fond. Ne pas y toucher.

## A. PRIORITÉ 1 — l'encre garde la COULEUR (momo)

Symptôme : les hiragana sortent en **blanc pur ou quasi noir**. Cause : `Theme.inkOn` part de
`theme.text` (gris neutre) et le pousse par `Qt.lighter/darker` jusqu'au contraste → à la fin il ne
reste plus aucune teinte. Momo veut « la couleur, mais vraiment plus claire ou plus foncée ».

Règle à implémenter (dans `Theme.qml`) :

1. Nouvelle fonction `tint(base, bgLum, target, light)` : mélange **minimal** de `base` vers blanc
   (`light = true`) ou vers noir jusqu'à atteindre `target` d'écart de luminance avec `bgLum`. Mélange
   minimal = on garde le maximum de saturation possible pour ce contraste. (Sonde binaire sur le ratio,
   8 itérations suffisent ; pas de boucle non bornée.)
2. `inkOn(bgLum)` = `tint(mix(text, accent, 0.25), …)` — la teinte vient de l'accent, le gris de la
   palette n'est plus qu'une base. Si le contraste obtenu reste < 0.42, repli sur `contrastOn(text, …)`
   (comportement actuel) : on ne livre jamais une encre illisible pour une raison esthétique.
3. `accentInk(bgLum)` = `tint(accent, …)` (teinte conservée, jamais mélangée vers le gris) ; l'accent
   des suffixes じ / ふん doit rester **reconnaissable comme la couleur du fond**, en clair sur fond
   sombre, en foncé sur fond clair.
4. Interdit : écrire une couleur en dur. Tout dérive de `Theme.text` / `Theme.accent` / `Theme.bgSolid`
   par `mix` + `tint`.
5. Preuve statique à joindre : un petit calcul Python (dans ton rapport, pas un fichier du dépôt) qui
   montre, pour `bgLum = 0.143` et `0.235`, la couleur finale des deux encres en RGB et le contraste
   obtenu — les valeurs doivent rester **teintées** (canal max − canal min ≥ 12 sur 255) et le
   contraste ≥ 0.42.

## B. Animations — sobres, gratuites, réactives

1. Transition de couleur quand le fond change : `Behavior on color { ColorAnimation { duration: 220 } }`
   sur `ink` / `inkDim` / `accentInk` **dans `WidgetBase`** (une seule fois, tous les widgets en
   héritent) et sur le remplissage du panneau dans `cc/main.qml`.
2. Apparition d'une carte : opacité 0.85 → 1 sur 160 ms, `Easing.OutCubic`. Aucune animation de
   géométrie (le drag/resize doit rester instantané).
3. **Interdits** : `ShaderEffect`, `MultiEffect`, `BackgroundEffect`, blur, `NumberAnimation` sur une
   valeur qui change à chaque frame (cava, jauges), toute animation > 320 ms, tout `Timer` < 1 s.
4. Aucun `Behavior` quand `editing` est vrai (le Studio doit rester sec).

## C. Sécuriser

1. `widgets_json.py` : `margin` / `gap` bornés (0..512) à l'entrée de l'op `autoplace` (`float()` dans un
   `try`, sinon `OpError` lisible), `strategy` validée contre `autoplace.STRATEGIES` (déjà fait),
   `host` validé (déjà fait). `setplacement` : refus explicite si aucun placement mémorisé (déjà fait).
2. `apply-wallpaper.sh` : le `curl` de `reapply` garde son `-m 6` et `|| true` ; payload statique, aucun
   argument externe interpolé. Ne pas ajouter de `jq`/`python` dans cette chaîne.
3. `Theme.qml` : toute lecture de `lumValues` vérifie `length === 32*18` (déjà) ; `lumAt` doit renvoyer
   `-1` (jamais `NaN`) pour une boîte vide ou inversée.
4. Pas de nouvelle dépendance, pas de nouveau fichier exécutable, pas de nouvelle unité systemd.

## D. PRIORITÉ 2 — rien de persistant, tout instantané

Momo : « pas de process gourmand, très léger, facile, instantané, pas de process inutile externe ».

1. **Supprimer le polling de luminance.** `theme-apply.py` écrit déjà la palette : il doit aussi écrire
   `lumgrid` (les 576 valeurs, une ligne JSON) dans `${XDG_RUNTIME_DIR:-/tmp}/sasquatch-lumgrid.json`
   (créer le dossier si absent, écriture atomique `os.replace`). Même endroit que le lock de palette.
2. `Theme.qml` : remplacer `lumTimer` par un `FileView { path: <ce fichier>; watchChanges: true }` +
   `onTextChanged` → `readLumgrid(JSON.parse(text))`. **Zéro timer, zéro requête** : l'encre suit le
   changement de papier peint à la frame suivante. Garder `refreshLumgrid()` (API) comme **repli
   unique** au démarrage si le fichier n'existe pas — un seul appel, pas de boucle.
3. Ne pas toucher au `paletteTimer` existant (5 s) : hors périmètre.
4. Preuve statique : `grep -n "Timer" Theme.qml` ne doit plus montrer de `lumTimer`, et
   `grep -c "http" Theme.qml` ne doit pas augmenter.

## E. Fichiers autorisés (uniquement)

`cc/widgets/Sasquatch/Widgets/Theme.qml` · `WidgetBase.qml` · `widgets/ClockWidget.qml` (bloc kana
seulement) · `cc/main.qml` (couleur du panneau + animation) · `scripts/theme-apply.py` (écriture du
lumgrid en plus de la palette) · `cc/widgets_json.py` (bornes de `autoplace`).
**Ne pas** toucher : `registry.json`, `WidgetCanvas.qml`, `autoplace.py`, `apply-wallpaper.sh`,
`StudioPage.qml`, `hypr/hyprlock.conf`, `hypr/scripts/*`.

## F. Vérifications (statiques, tu les lances)

```bash
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml -I ~/.config/cc/widgets -I ~/.config/cc \
  ~/.config/cc/widgets/Sasquatch/Widgets/Theme.qml \
  ~/.config/cc/widgets/Sasquatch/Widgets/WidgetBase.qml \
  ~/.config/cc/widgets/Sasquatch/Widgets/widgets/ClockWidget.qml \
  ~/.config/cc/main.qml
python3 -m py_compile ~/.config/scripts/theme-apply.py ~/.config/cc/widgets_json.py
bash -n ~/.config/cc/apply-wallpaper.sh
grep -n "ColorAnimation\|NumberAnimation\|duration" ~/.config/cc/widgets/Sasquatch/Widgets/WidgetBase.qml
grep -n "Timer" ~/.config/cc/widgets/Sasquatch/Widgets/Theme.qml
```
Attendu : 0 diagnostic `Warning:`/`Error:` sur les 4 QML (les « unqualified access » de
`WidgetCanvas.qml` ne font pas partie du lot), `py_compile` muet, plus aucun `lumTimer`.

## G. Checklist pour Asuka (il exécute, pas toi)

1. `systemctl --user restart sasquatch-cc` puis `--user restart sasquatch-bg` (rechargement du module).
2. Rendu du fond hors écran : `SASQUATCH_BG_GRAB=/tmp/bg.png` + restart de `sasquatch-bg`, composer sur
   le papier peint, lire les couleurs des deux cartes (teinte conservée ? contraste ?).
3. Changer de papier peint (clair ↔ sombre) et vérifier que l'encre bascule **sans timer** :
   `journalctl --user -u sasquatch-bg` ne doit plus montrer de requête périodique, et le rendu doit
   suivre dans la seconde.

## H. Rythme

**Code d'abord, UNE passe de vérification à la fin** (les commandes de §F), pas de cycles de rendu
successifs — je ne peux pas te laisser relancer des harnais sur la session de momo. Si une preuve est
impossible sans lancer le shell, écris-le et passe. Rapport court : fichiers touchés, valeurs d'encre
calculées (§A.5), ce que tu n'as pas pu vérifier.
