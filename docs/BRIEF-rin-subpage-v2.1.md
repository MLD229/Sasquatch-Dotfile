# BRIEF Rin — subpage v2.1 : DEUX causes racines trouvées, à corriger

Date : 2026-10-29 (soir)
Auteur : Asuka — mesures faites sur la session réelle de momo
Destinataire : Rin

## CE QUI RESTE CASSÉ (preuves, pas suppositions)

Ta refonte layer-shell est structurellement bonne (plus de piège de mapping,
plus d'`alterzorder`, texte net avec une fenêtre dedans). Mais **la page vide
n'affiche toujours RIEN** — c'est exactement ce que momo reproche.

### Cause 1 — `misc:close_special_on_empty` (défaut Hyprland = 1)
```
$ hyprctl getoption misc:close_special_on_empty
int: 1
set: false          # jamais défini dans la config
```
Conséquence mesurée : ouvrir une sub page **vide** → Hyprland la referme
instantanément (le `specialWorkspace` disparaît en < 1 s). Le script toggle,
puis plus rien.

### Cause 2 — un special workspace est un OVERLAY, pas une page
Même avec `close_special_on_empty = false` (testé à chaud) :
```
hyprctl monitors -j  → specialWorkspace: special:subpage (id -98)
hyprctl workspaces   → -98 special:subpage, windows: 0
state.py             → open eDP-1
hyprctl layers       → namespace subpage présent
grim                 → on voit TOUJOURS le bureau (Discord + terminal)
```
Avec une fenêtre dedans (`[workspace special:subpage silent] kitty`), elle
s'affiche **par-dessus** le bureau. Donc : Hyprland superpose les fenêtres du
special au workspace courant, il ne dessine **pas** de fond de page. Une page
vide = écran inchangé.

Conclusion : **la « page » doit être dessinée par ta surface layer**, pas
attendue du compositeur.

## CORRECTIONS DEMANDÉES

### 1. Config Hyprland (obligatoire)
Ajouter dans `hypr/conf.d/general.conf` (section misc) :
```
misc {
    close_special_on_empty = false
}
```
(syntaxe hyprlang de ce dépôt ; si le fichier utilise des lignes plates
`misc:xxx = y`, garde le style existant). Sans ça, la page vide se ferme seule.

### 2. La surface layer devient la page (le vrai correctif)
Dans `subpage/shell.qml`, quand `specialOpen` est vrai :
- **Fond de page** : un voile sombre couvrant le panneau (ex. noir alpha
  ~0.55) — assez dense pour qu'on voie clairement « une page » et non le
  bureau derrière. **Pas de blur compositeur** (leçon du bug précédent) ;
  `BackgroundEffect` doux est toléré seulement si tu prouves au pixel que le
  texte du dessous reste net — sinon, voile simple.
- Coins en L + étiquette `サブページ` **par-dessus** le voile (contraste
  suffisant : l'accent de la palette doit ressortir sur le voile).
- **Clics** : le voile doit **capter** les clics (région d'entrée = surface
  entière quand la page est ouverte). Raison : sinon un clic au centre tombe
  sur le bureau caché (Discord, etc.) alors que l'utilisateur croit cliquer
  dans la page. Les fenêtres envoyées dans le special sont **au-dessus** de la
  surface, elles restent cliquables normalement.
- La surface ne doit JAMAIS apparaître quand la page est fermée (surface
  démontée, 0 process après fermeture — c'est déjà le cas, ne régresse pas).

### 3. `state.py` : une seule source de vérité
La voie rapide par socket a renvoyé `closed` alors que `hyprctl` disait
`open` (observé). Soit tu la supprimes, soit tu la valides en re-testant avec
`hyprctl monitors -j` en cas de désaccord. **Jamais** de décision sur une
donnée socket non confirmée. Un écart entre `state.py` et `hyprctl` = bug.

### 4. Ne pas régresser ce qui marche
- fenêtre envoyée dans la page → visible, nette, cliquable ;
- ouverture/fermeture sans vol de focus (`hyprctl activewindow -j` identique) ;
- fermeture par `hyprctl dispatch togglespecialworkspace subpage` → la surface
  disparaît seule ;
- zéro process après fermeture (le process peut sortir après ~5 s).

## VÉRIFICATION (exige des preuves que je peux refaire)
Env : `HYPRLAND_INSTANCE_SIGNATURE=efb50993780079460b0cbed1363e2166a2de1d9f_1793270119_434835009`,
`XDG_RUNTIME_DIR=/run/user/1000`, `WAYLAND_DISPLAY=wayland-1`, `DISPLAY=:0`.

1. **Page VIDE ouverte** : `subpage.sh` → colle
   `hyprctl monitors -j` (special id -98), `state.py` (open), `hyprctl layers`
   (namespace subpage), **et la capture `grim`** : on doit voir un voile sombre
   + 4 coins + étiquette, **PAS** Discord. Regarde l'image.
2. **Après 10 s** la page vide est toujours ouverte (preuve que
   `close_special_on_empty=false` est actif et pris en compte).
3. **Page avec une fenêtre** (`[workspace special:subpage silent] kitty
   --title TEST-SUBPAGE`) : la fenêtre est visible et nette, les coins restent
   visibles dans la marge. Ferme la fenêtre de test à la fin.
4. **Clics** : prouve la région d'entrée (code + `WAYLAND_DEBUG` si tu peux) ;
   dis honnêtement si le clic réel n'a pas pu être testé.
5. **Fermeture** : plus de layer, plus de process, bureau intact.
6. `qmllint` + `py_compile` + `bash -n`, et `tests/verify.sh` à jour → colle le
   total OK/FAIL.

## RÈGLES
- Ne touche pas `cc/sidebar` ni `aiko`. Pas de commit.
- momo utilise sa session (Discord/jeu) : reste bref, remets tout en état,
  ferme ta fenêtre de test, ne laisse rien ouvert.

## LIVRABLE
Les sorties collées, les 2 captures regardées (vide + avec fenêtre), ce qui est
corrigé, ce qui reste fragile.
