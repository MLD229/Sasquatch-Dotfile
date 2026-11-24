# BRIEF v4 — Barre verticale : finitions + dette technique (2026-10-31, soir)

**RÈGLE : momo travaille sur sa machine. Tu ne lances RIEN.**
Interdits : `systemctl restart/stop/start` (sasquatch-bar, waybar…), `quickshell -p`, `bar.sh`,
`tests/run-all.sh`, `tests/verify-v2.sh`, `hyprctl dispatch`, rofi, `notify-send`, `qs ipc call`
d'une fonction d'action. Autorisé : lecture, `qmllint`, `bash -n`, `py_compile`, `git status`, `grep`,
calculs. Toute preuve dynamique est différée → checklist pour momo à la fin.

État en service (ne pas casser) : barre verticale **40 px**, style **îlots** (aucune dalle :
`panelAlpha` 0), pilules `cardAlpha` 0.86, blur actif, waybar **retirée** (unité liée mais
`disabled`, `theme-apply.sh` et `apply-lang.sh` ne la lancent plus), indicateur de défilement des
apps supprimé. `~/.config/cc` → dépôt : tes fichiers sont live au prochain restart, pas avant.

Lis `cc/bar/README.md` (§10 corrections Asuka, §11 décisions) et `docs/BRIEF-rin-barre-v3.md`.

---

## A. Rythme vertical et uniformité « de partie en partie »

1. **Pilule des workspaces trop haute.** Elle s'étire sur tout l'espace libre (points très espacés au
   milieu de la barre). Elle doit être **compacte** : hauteur = nombre de points × pas + padding
   (≈ 2 × `Config.inset`), centrée sur son groupe, points serrés régulièrement. L'espace libre va
   **entre** les groupes, jamais dans une pilule.
2. **Grand vide entre le volume et le bloc d'apps.** Supprimer l'étirement : chaque groupe prend sa
   hauteur naturelle, et la barre se répartit en **quatre groupes** :
   haut (recherche + workspaces) · info (débit + horloge + volume) · apps (épinglées + « + » + en
   cours) · bas (son/wifi/DND + engrenage). Un seul ressort d'espace : à parts égales entre les
   groupes (ou un écart fixe, au choix — mais **une seule règle**, pas deux).
3. **Uniformité des pilules** : même rayon, même padding interne, même hauteur de case pour tous les
   blocs ; les glyphes tombent sur le même axe optique (déjà calculé en v3 §5 — à réutiliser, pas à
   recalculer). Un bloc ne doit jamais être plus large que `Config.block`.
4. **Densité** : à 40 px de large, vérifier que rien ne colle (padding ≥ 3 px autour des glyphes,
   badges qui ne débordent pas de la pilule voisine).

## B. Deux choses non prouvées en v3 (à vérifier par le code, puis checklist)

5. **`WheelZone` ne doit avaler aucun clic.** Elle est en `NoButton`, mais si un bloc devenait muet au
   clic (loupe, app, toggle), c'est là que ça se joue. Relis l'empilement (z-order, `MouseArea` des
   modules par-dessus), et si le moindre doute subsiste : rends la zone **explicitement
   transparente aux clics** (`enabled: false` + `propagateComposedEvents`, ou suppression de la zone
   et `onWheel` posé sur le `MouseArea` existant du module — c'est plus simple et sans risque).
   Prends la solution la plus simple qui garantit qu'un clic passe toujours.
6. **Champ de recherche de la popup « + »** : focus clavier à l'ouverture, Échap ferme, Entrée prend
   le premier résultat. **Aucun grab global** (interdit : ça a bloqué hyprlock une fois).

## C. Comportements à finir

7. **Fermeture des popups** : Échap, clic sur une zone vide de la barre, clic sur un autre module
   (un seul popup à la fois). Pas de clic-extérieur global (pas de grab).
8. **Infobulle (`Tip`)** : elle ne doit jamais recouvrir la colonne de blocs (décalage à droite de la
   barre + largeur max + retour à la ligne), et doit disparaître au clic. Vérifier le cas d'une
   infobulle longue (« Subpage … — 1 fenêtre »).
9. **Workspaces persistants** : ajouter une clé `bar.persistentWorkspaces` (défaut **10**, comme
   l'ancienne waybar) : les points des workspaces inexistants s'affichent atténués et cliquables
   (dispatch). Valeur 0 = comportement actuel (seulement les workspaces existants). Purement piloté
   par `bar.json`, rechargement à chaud.

## D. Cohérence du dotfile

10. **`install.sh`** : waybar ne doit **plus jamais** être activée (le bloc actuel lie l'unité puis
    l'informe « déjà activée » puis la désactive plus bas — simplifier : lier, ne pas activer,
    l'arrêter si active, et mentionner que `theme-apply.sh`/`apply-lang.sh` ne la lancent plus).
    Vérifier aussi que `scripts/theme-apply.sh` et `scripts/apply-lang.sh` gardent bien leur garde.
11. **`README.md`** : mettre à jour le style (îlots, `panelAlpha` 0, `cardAlpha` 0.86, blur), la
    largeur 40, les nouvelles clés (`persistentWorkspaces`), le retrait de waybar avec la commande
    exacte de retour arrière, et les seuils de contraste mesurés (pilule ≈ `42,35,41`, wallpaper
    visible entre les îlots).
12. **`PROGRESS.md`** : une entrée v4 avec les pièges rencontrés (dont `pragma Singleton` — un
    singleton déclaré dans `qmldir` sans ce pragma tue tout le shell, service en `start-limit-hit`).

## E. Interdits / à ne pas toucher

- Ne pas remettre de fond de barre (`panelAlpha` reste 0 : c'est la demande de momo, une barre
  « uniforme mais de partie en partie »).
- Ne pas toucher aux apps épinglées de `bar.json` (dont `org.kde.krita`) : c'est le choix de momo.
- Ne pas modifier `cc/main.qml`, `cc/sidebar/`, `cc/server.py`, `settings/`, `theme-apply.py`,
  `waybar/`, `~/.config/rofi/`.
- Aucune couleur en dur hors `BarPalette.qml`, pas de grab clavier, `qmllint` après chaque édition,
  commentaires `//` uniquement en QML.

## F. Rapport attendu

1. Fichiers modifiés + `git status --short`, staging **fichier par fichier**.
2. `qmllint` (Qt6 : `/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml`), `bash -n`, `py_compile`.
3. Schéma vertical retenu : hauteurs calculées de chaque groupe + position attendue de chaque bloc,
   en nombres (pas une capture).
4. Ce qui a changé pour les clics (§5) et pourquoi c'est désormais sans risque.
5. **Checklist momo en 2 minutes** : une ligne par point de A/B/C, avec en tête
   `systemctl --user restart sasquatch-bar`.
6. Ce qui reste non prouvable sans toucher au bureau.
