# BRIEF rin — Chasse aux bugs + mécanismes (add, visualizer, variantes, fond)

Repo `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`). Backend réparé : `/api/widgets` et `/api/notes`
répondent 200. Contrat/widgets : `docs/BRIEF-rin-widgets-v1.md` §2/§3/§9. Copies : `docs/SPEC-copy-widgets.md`.

Demande de momo : « peaufiner, réparer les bugs, en trouver d'autres et les corriger — genre l'ajout
(add) et le visu (visualizer), bref les mécanismes et les problèmes ».

## 1. Mécanisme d'AJOUT (Studio + API) — priorité 1

À tester puis corriger, dans cet ordre :

1. `add` sur `host: "cc"` → la géométrie par défaut ne doit **jamais chevaucher** une instance existante
   (chercher la première cellule libre sur la grille 12 colonnes, pas un coin fixe).
2. `add` sur `host: "background"` → `x`/`y` en fraction, décalage en cascade (0.02 par instance), et
   `x + w/écran <= 1` (clamp).
3. **Identifiant unique** : `<type>-<n>` jamais réutilisé, même après suppression (pas de collision entre
   deux instances du même type).
4. **Apparition sans redémarrage** : après le POST, l'hôte concerné relit `widgets.json` (révision qui
   change) et affiche la nouvelle instance. Prouver pour les deux hôtes, sans `systemctl restart`.
5. `add` d'un type dont `component` est vide → refus 400 avec message clair (pas une instance fantôme).
6. **BUG CONNU À CORRIGER** : le masque d'entrée du fond d'écran (`cc/background/shell.qml`) déclare
   **8 emplacements fixes**. Un 9ᵉ widget de fond n'a donc aucune zone cliquable. Le masque doit se
   construire à partir des instances réelles (tableau de Regions généré par le `Repeater`/le nombre
   d'instances), sans plafond codé en dur — et sans région nulle pour les emplacements vides.

## 2. Variantes — priorité 2

- `media` **`visualizer`** : carte absente (`showCard: false`), cava seul, **aucun** transport, aucune
  pochette, aucun texte. Vérifier qu'elle se charge seule (harnais) et depuis le Studio.
- Changement de variante par le Studio → rendu immédiat, taille cohérente avec le registre (cellules CC,
  `w`/`h` du fond re-clampés), et `implicitWidth/Height` corrects pour les 15 widgets x leurs variantes.
- Aucune variante ne doit produire un cadre vide ou un texte tronqué : si une variante n'a rien à montrer
  à cette taille, elle doit l'assumer (ex. `compact` = une seule ligne d'info).

## 3. Interactions du fond d'écran — priorité 3

- Hors édition : seuls les widgets `live` réagissent (clic = ouvre le CC), les autres laissent passer.
- En édition : drag + poignée de resize, curseur correct, contour accent, un seul POST au relâchement.
- Re-clamp après changement de résolution / multi-écran.
- Vérifier qu'un clic sur une zone vide du fond traverse bien (pas de surface qui avale tout).

## 4. Défauts visuels connus (mes pages, à corriger sur place, pas à réécrire)

`cc/pages/ToolsPage.qml` et `SystemPage.qml` + `GlassCard.qml` (module) sont **ma base** :
- l'espacement vertical entre les 4 cartes d'Outils est trop grand : les cartes doivent s'empiler
  serrées (écart `Theme.spacing`), la page ne doit pas étirer ses blocs ; garder la dernière carte du bas
  alignée en haut, pas étirée sur la hauteur restante ;
- `Traduire` : la zone de résultat ne doit apparaître qu'après une traduction, et le bloc ne doit pas
  changer de hauteur quand elle apparaît (réserver la place) ;
- cohérence : une carte de page et une carte du board doivent être indiscernables (mêmes alphas, halo,
  rayons, interlignes).

## 5. Méthode imposée

Créer `cc/widgets/tests/bugs.sh` qui, sur les deux hôtes, joue : `add` → `move` → `resize` → `variant`
→ `rm`, vérifie chaque étape par `GET /api/widgets` (révision + valeur relue) et capture le rendu.
Chaque bug corrigé = une ligne du tableau `symptôme → cause → correctif → preuve (commande + sortie)`.
Un bug non corrigé reste listé avec la raison — jamais effacé.

Interdits (brief v1 §9) inchangés : jamais `cc/main.qml` en plein écran, keybinds intouchés, fichiers non
commités de momo intouchés, `pkill` crocheté, commentaires `//`, aucune couleur en dur.
