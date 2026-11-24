# BRIEF v2 — Barre verticale : polish demandé par momo (2026-10-31)

Suite de la v1 (`cc/bar/` livré, en service, waybar débranchée). **Ne réécris pas l'architecture** :
PanelWindow gauche + service `sasquatch-bar` + `bar.json` + palette via `/api/palette` restent.
Lis d'abord `cc/bar/README.md` (§10 = corrections déjà appliquées par Asuka : `bar.sh` pilote le
service par `systemctl`, pastille d'initiale pour les icônes non résolues, `bar.json` épinglant
dolphin au lieu de vlc). Ne reviens pas en arrière sur ces points.

Machine : Hyprland 0.56.2, Quickshell 0.3.2, 1 écran eDP-1 1920×1080. Backend CC actif 8765.
Panneau Settings réel : `~/.config/settings/settings.sh` (backend 8770, Super+I).

---

## 1. Clic sur une app = « m'amener là-bas »

Aujourd'hui `Hypr.focusClass()` lit une adresse dans un cache puis `dispatch focuswindow address:` —
d'où les `WARN … No such window found` dans le journal, et parfois rien ne se passe.

Attendu :
- clic sur une app **ouverte** → l'écran va sur **sa fenêtre**, y compris si elle est sur un autre
  workspace (changement de workspace + focus), puis la fenêtre est réellement focalisée.
- clic sur une app **fermée** (épinglée) → lancement, comme aujourd'hui.
- plusieurs fenêtres → on va sur la plus récemment active (pas une fenêtre morte du cache).

Implémentation robuste obligatoire :
1. résoudre l'adresse **au moment du clic** (relire les toplevels), pas depuis une valeur mémorisée ;
2. `Hyprland.dispatch("focuswindow address:0x…")` ;
3. si l'adresse a disparu entre-temps → repli : lire le workspace de la classe, `dispatch workspace <ws>`,
   puis re-tenter une fois.

Preuve à fournir : deux fenêtres kitty sur deux workspaces, clic simulé par le même chemin de code
(ex. `qs ipc call bar <fn>`) → `hyprctl activewindow` montre la bonne classe **et** `hyprctl activeworkspace`
le bon workspace. Pas de capture d'écran comme seule preuve.

## 2. Boutons — « fix les boutons »

- Chaque bouton doit avoir une cible cliquable **≥ 38 px** (même si le glyphe fait 18 px) et la zone
  cliquable doit couvrir exactement la zone visuelle (pas de bouton qui « bouge » sous le curseur).
- Tous les boutons documentés doivent répondre : loupe, chaque workspace, débit (popup), horloge
  (calendrier), slider volume (clic + molette + drag), chaque app (gauche/droit/molette), toggles
  son/wifi/DND, engrenage, croix des popups.
- Un bouton dont la cible est introuvable (app désinstallée, outil absent) doit **dire pourquoi**
  (notification ou état visible), jamais un clic silencieux.
- Livrer un tableau « bouton → action → commande de vérification » et le résultat de chaque ligne.

## 3. Transparence : « on ne voit presque que les plugins »

- Fond de barre quasi invisible : alpha panneau ≈ **0.22–0.30** (au lieu de 0.75).
- Blocs/pilules : alpha ≈ **0.16–0.24** (au lieu de 0.55) ; bordure visible seulement au survol
  (sinon 0–0.15).
- **Icônes et texte restent à 100 % d'opacité** : la lisibilité ne baisse pas, c'est le fond qui
  disparaît. Le contraste texte/fond doit rester conforme (pas de gris sur gris).
- Le survol et l'état actif doivent rester perceptibles : c'est là que le fond remonte (α ≈ 0.35).
- Le flou (`BackgroundEffect`) reste demandé mais ne doit pas créer de voile laiteux sur un fond
  aussi transparent : si le rendu devient laiteux, baisser `radius` (≤ 10) plutôt que l'alpha.
- Toutes ces valeurs passent par `bar.json` (`appearance.panelAlpha`, `cardAlpha`, `hoverAlpha`) —
  rien en dur — et restent appliquées à chaud.

## 4. Plus fin, sans perdre en qualité

- Largeur de barre : **56 → 46 px** dans `bar.json` (`bar.width`), et le code doit rester correct à
  44 comme à 56 (aucune taille codée en dur en dehors de `bar.json`).
- Conséquence à traiter : les blocs font aujourd'hui 34–40 px dans une colonne de `width-16` — ils
  doivent être **recalculés** (≈ 30–32 px, marges latérales 6–8) pour ne pas déborder.
- Glyphes d'app 22 → 20 px, glyphes d'icônes 18 → 16-17 px, chiffres de l'horloge : pas en dessous de
  14 px, débit pas en dessous de 9 px (lisibilité prioritaire sur la finesse).
- Vérifier au pixel : crop `grim -g "<x> <y> <w> <h>"` agrandi ×3, et lire les chiffres à l'œil —
  « fin » ne veut pas dire « illisible ».

## 5. Centrage

- **Un seul axe vertical** : tous les blocs ont le même centre horizontal que la barre (à ±1 px).
  Aujourd'hui les colonnes sont centrées mais les blocs de 34 px dans une colonne de 40 px sont
  alignés à gauche → décalage visible.
- Utiliser un `ColumnLayout` avec `Layout.alignment: Qt.AlignHCenter` (ou `anchors.horizontalCenter`
  sur chaque enfant) plutôt qu'un `Column` qui laisse les enfants à gauche.
- Hauteurs de blocs homogènes dans chaque zone, espacement régulier (même valeur partout, pas 6 ici
  et 8 là), et glyphes centrés **dans** leur pilule (vérifier visuellement, certains Nerd Font ont des
  métriques asymétriques).
- Preuve : pour 3 blocs, mesurer la position du centre à partir de la capture (x + w/2) et montrer que
  les valeurs sont identiques.

## 6. Paramètres : mauvais lien à corriger

L'engrenage lance `~/.config/cc/cc.sh` (Control Center) — **ce n'est pas le panneau de réglages**.
Le vrai panneau du dotfile : **`~/.config/settings/settings.sh`** (fenêtre « Sasquatch Settings »,
backend HTTP 8770, raccourci Super+I, c'est lui qui écrit `keybinds-user.conf`, `settings.json`,
`hypridle.conf`…).

- Clic engrenage → `hyprctl dispatch exec ~/.config/settings/settings.sh`.
- Infobulle : « Réglages (Super+I) ».
- Le Control Center reste accessible ailleurs (il ne disparaît pas), mais ce n'est plus ce bouton.
- Vérifier que **la fenêtre s'ouvre vraiment** : `hyprctl clients -j | grep -i "Sasquatch Settings"`
  + capture, pas seulement « le process a démarré ». Si le panneau Settings est déjà ouvert, le
  script le ferme (c'est un toggle) : le test doit tenir compte de ça.

---

## 7. Contraintes inchangées

- Aucune couleur en dur (tout vient de `/api/palette`, valeurs de secours commentées seulement).
- `bar.json` reste la seule source des options, rechargement à chaud, JSON cassé = config précédente.
- `bar.sh` continue de passer par `systemctl --user start/stop sasquatch-bar` (ne pas revenir à `exec quickshell`).
- `qmllint` après chaque édition QML, commentaires `//` uniquement, `bash -n` sur les scripts.
- Ne pas toucher `cc/main.qml`, `cc/sidebar/`, `cc/server.py`, `settings/`, `theme-apply.py`, `waybar/`.
- Pas de grab de focus clavier sur les popups (leçon du blocage hyprlock).
- La barre doit rester utilisable si le backend tombe (états « indisponible »).
- Stage explicite (`git add` fichier par fichier) ; ne pas emporter les modifications non liées du dépôt.

## 8. Rapport attendu

- Tableau « bouton → action → preuve ».
- Les crops avant/après (dans `cc/bar/tests/artifacts/`), avec les chiffres : alpha, largeur,
  centre de chaque bloc, taille des glyphes.
- Preuve du changement de workspace au clic d'app (deux fenêtres, deux workspaces).
- Preuve que l'engrenage ouvre **Sasquatch Settings**.
- `git status --short`, ce qui est staged, ce qui ne l'est pas.
- Ce qui n'a pas pu être testé en réel (souris non simulable sur ce poste) et pourquoi.
