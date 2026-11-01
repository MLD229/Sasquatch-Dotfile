# BRIEF rin — Transparence réelle, suppression des filets blancs, Studio à jour

Repo `~/Downloads/Sasquatch-Dotfile` (= `~/.config/cc`). Contrat : `docs/BRIEF-rin-widgets-v1.md` §2/§9.
Retour direct de momo, dans ses mots : « il y a des traits blancs fins dans les widgets qui ne devraient
pas être là ; les widgets doivent être transparents SANS blur mais les composants visibles ; et dans la
partie ajout de widgets, les widgets placés sont invisibles, je pense que ce n'est pas à jour ».

## 1. Supprimer les filets blancs (bug visuel)

Deux sources, à retirer :

1. **`cc/widgets/Sasquatch/Widgets/WidgetBase.qml` ligne ~173-181** : le « filet clair de 1 px en haut »
   (`color: Theme.light`) — c'est un trait blanc qui court sur chaque carte. **Le supprimer**, pas le
   réduire.
2. **Les bordures au repos** (`border.color: Theme.border` dans `WidgetBase.qml` et `GlassCard.qml`) :
   au repos la carte n'a **aucun contour visible**. Le contour n'apparaît qu'en `editing` (accent, pour
   le drag) ou en survol actif d'un bouton — jamais en permanence.
3. Vérifier qu'aucun autre trait blanc ne subsiste : `grep -n "Theme.light\|border.width: 1" ` dans le
   module et dans `pages/` ; un `border.width: 1` sans besoin explicite est supprimé.

## 2. Transparence SANS blur (décision nette)

- **Aucun flou** : supprimer le `MultiEffect` (halo) de `WidgetBase.qml` ET de `GlassCard.qml`, et tout
  `BackgroundEffect` / `blurRegion` s'il en reste dans un hôte. Plus de `blurEnabled`.
- Remplissage : **très léger mais lisible** — `alpha` de carte ≈ **0.06 à 0.10** (au lieu de 0.13),
  hero ≈ 0.05. Le fond ne doit pas former de plaque : ce sont les **contenus** (textes, icônes, jauges)
  qui doivent rester à 100 % d'opacité et porter l'information.
- Le token `style.blur` reste dans le schéma (compatibilité) mais **n'est plus appliqué** : documenter
  « option conservée, sans effet » plutôt que de le retirer du JSON (le Studio l'afficherait cassé).
- Contrôle : sur une capture, aucune zone grise uniforme autour des textes ; les glyphes et les barres
  restent nets et pleinement opaques.

## 3. Studio : les widgets placés doivent être VISIBLES

Symptôme : dans l'espace d'ajout, les widgets posés sur l'aperçu du fond n'apparaissent pas / ne se
mettent pas à jour.

- Cause la plus probable : la mise à l'échelle de l'aperçu (`scale` sur le conteneur) combinée à un
  `visible`/`opacity` hérité, ou un chargement du composant avant que le registre ne soit prêt
  (`Loader.source` vide → jamais rechargé).
- Correctif attendu : dans l'aperçu, chaque instance de fond doit être rendue par le MÊME composant que
  l'hôte réel (registre → `Loader`), avec `variant` et `style` de l'instance, et l'aperçu doit se
  rafraîchir après chaque `add`/`move`/`style` (relire la réponse du POST, ne pas attendre un restart).
- Preuve obligatoire : poser un widget depuis le catalogue, le voir apparaître **sans redémarrer**,
  puis capturer l'aperçu (self-grab du harnais d'aperçu).
- Si l'aperçu ne peut pas rendre un composant (chemin de composant vide), afficher une vignette
  d'attente explicite au lieu d'un trou invisible.

## 4. Méthode

Code d'abord, **une seule** passe de vérification à la fin (qmllint Qt6 + une capture d'ensemble + un
`curl /api/widgets`). Pas de boucles de rendu. Chaque point corrigé = une ligne
`symptôme → cause → correctif → preuve`. Interdits inchangés (brief v1 §9) : jamais `main.qml` en plein
écran, keybinds intouchés, fichiers non commités de momo intouchés, `pkill` crocheté, commentaires `//`.
