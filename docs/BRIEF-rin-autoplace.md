# BRIEF rin — Placement intelligent des widgets (Studio + API)

Repo `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`). Backend 8765. Contrat widgets :
`docs/BRIEF-rin-widgets-v1.md` §2/§4/§9. Décision de momo : « une option de placement intelligent qui
prend tout en compte, inspiré du placement du clock existant (par thème), avec le nombre, l'espacement
et les collisions — bref différents choix ».

## 0. Le modèle à copier : le wallclock existant

`~/.config/waybar/scripts/wallclock-ja.py` → `find_smart_position()` **est la référence**. Formule
exacte, à reprendre telle quelle pour la stratégie `theme` :

```
grille 32x18 (GRID_W/H), fenêtre de CLOCK_CELLS_W/H cellules, pas de 2
score = luminance_moyenne * 1.0          # zone SOMBRE prioritaire
      + ecart_type_moyen   * 0.5         # zone PLATE (pas de détail sous le texte)
      + max(0, 3 - bord)   * 2.0         # pénalité bord (coins autorisés)
choisir la fenêtre de score MINIMAL ; le widget est CENTRÉ sur cette fenêtre
```

Convertis en pixels écran comme le fait le script (échelle `max(scr_w/iw, scr_h/ih)` + offsets de
recadrage), puis **applique les contraintes ci-dessous** (le wallclock ne les a pas, il est seul).

## 1. Stratégies à offrir (différents choix)

| id | Nom affiché | Règle |
|---|---|---|
| `theme` | `Thème` | formule ci-dessus, un widget par zone (les suivants prennent la meilleure zone encore LIBRE) |
| `auto` | `Auto` | même score, mais **collisions d'abord** : on part de `theme` et si la place manque, on descend la liste des meilleures zones |
| `grid` | `Grille` | aligne sur une grille (cellules de 8 px côté fond, 12 colonnes côté CC), coins arrondis au multiple |
| `stack` | `Empilé` | colonne/ ligne le long d'un bord (`corner`: `tr|tl|br|bl`), empilement avec `gap` |
| `center` | `Centré` | centré horizontalement, empilement vertical |
| `spread` | `Réparti` | répartition régulière : `cols = ceil(sqrt(n))`, marges et `gap` respectés |

Chaque stratégie reçoit `margin` (bord d'écran, défaut 24), `gap` (entre widgets, défaut 12),
`corner` (pour `stack`), et une liste d'`ids` à replacer (défaut : tous les widgets de l'hôte).

## 2. Contraintes communes (aucune exception)

1. **Collision** : deux rectangles ne se chevauchent JAMAIS, `gap` inclus (AABB élargie de `gap/2`).
2. **Marge** : tout widget reste à `margin` px des bords de l'écran.
3. **Écran** : `x` reste une fraction 0..1, `y` aussi ; `w`/`h` en px. Recalcul après changement de
   résolution (les contraintes s'appliquent à la taille d'écran passée en paramètre, jamais en dur).
4. **Widgets existants** : les instances qui ne sont pas dans `ids` sont des **obstacles** (on ne les
   déplace pas, on les évite).
5. **Aucune place** : on ne force pas. Réponse `ok: false` + `unplaced: [ids]` + raison lisible
   (« plus de zone libre avec ces marges »).
6. **Déterminisme** : deux appels identiques sur le même état donnent le même résultat (pas de random).

## 3. API (un seul écrivain : `widgets_json.py`)

Ajouter `op: "autoplace"` à `POST /api/widgets` :

```json
{"op":"autoplace","host":"background","strategy":"theme","margin":24,"gap":12,"corner":"tr","ids":["clock-1"]}
```

- calcule les nouvelles géométries en Python (`cc/autoplace.py`, fonctions pures + testables),
- applique via l'écrivain existant (une seule révision, écriture atomique),
- répond `{"ok":true,"revision":N,"placed":[{id,x,y,w,h}],"unplaced":[],"strategy":"theme"}`,
- `strategy:"auto"` par défaut, et `GET /api/widgets` inchangé.

`autoplace.py` doit fonctionner **sans numpy/PIL** (repli : `theme` → `stack` en haut à droite), et
utiliser PIL si présent. Il réutilise la grille de luminance déjà servie par
`/api/wallpaper/lumgrid` quand elle est disponible (évite de rouvrir l'image).

## 4. Studio (l'espace widget)

Panneau « Placement intelligent » dans `cc/pages/StudioPage.qml` :
- sélecteur de stratégie (les 6 ci-dessus, libellés français),
- deux curseurs `Marges` (8–96) et `Espacement` (0–48) avec la **valeur relue**,
- choix du coin (visible seulement pour `Empilé`),
- bouton `Placer les widgets` → POST `autoplace` sur l'hôte affiché, puis relecture de `widgets.json`
  et rafraîchissement de l'aperçu (mêmes composants que l'hôte réel) ;
- le panneau affiche le résultat réel : `N placés`, et `M non placés · raison` en clair ;
- si la stratégie échoue, le message reste dans le panneau (pas de toast fugace).

## 5. Tests (obligatoires, script `cc/widgets/tests/autoplace.sh`)

Pour chaque stratégie, sur un état de test (3, puis 5 instances de tailles différentes) :
- aucune paire ne se chevauche (`gap` inclus) ;
- tous les rectangles à `margin` des bords ;
- tous les `x`,`y` dans 0..1 ;
- déterminisme (deux appels → mêmes géométries) ;
- cas « plus de place » : marges énormes → `ok:false` + `unplaced` non vide, et **rien n'est déplacé**.
Le script doit restaurer l'état de départ à la fin (`widgets.json` sauvegardé/restauré).

## 6. Rythme

Code d'abord, **une seule** passe de vérification à la fin : `python3 -m py_compile`, `qmllint` Qt6 sur
le Studio, `bash autoplace.sh`, plus une capture du Studio avec le panneau. Pas de boucles de rendu.
Interdits du brief v1 §9 inchangés (jamais `main.qml` en plein écran, keybinds intouchés, fichiers non
commités de momo intouchés, `pkill` crocheté, commentaires `//`).
